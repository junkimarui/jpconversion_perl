package IMEJP;
use strict;
use warnings;
use marisa;
use Encode;
use DBI;
use StopWatch;
use Storable;

our $bos = 0;
our $eos = 0;

sub new {
    my ($class, %args) = @_;
    my $self = {};
    bless($self, $class);
    $self->{chunk} = {};
    $self->{trans} = readCache($args{cache_file});
    $self->{trans_count} = {};
    $self->{trie} = new marisa::Trie;
    $self->{trie}->load($args{trie_file});
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$args{database_file}") or die "Can't open database $!";
    $self->{last_id} = 0;
    $self->{bestk} = $args{bestk} // 1;
    $self->{debug} = $args{debug} // 0;
    return $self;
}

sub readCache {
    my $cache_file = shift;
    return {} if (!$cache_file);
    open (my $cache_fh, "<", $cache_file) or return {};
    my %trans;
    while (my $line = <$cache_fh>) {
	chomp($line);
	my @k = split(",",$line);
	$trans{$k[0]}{$k[1]} = $k[2];
    }
    return \%trans;
}

sub convert {
    my ($self, %args) = @_;
    my $input = $args{input};
    utf8::decode($input);
    $self->{watch} = new StopWatch;
    $self->{last_id} = $self->getMaxUnivID();
    my ($node, $link, $state) = ($self->{debug}) ? 
	$self->createGraphDebug($input) : $self->createGraph($input);
    $self->{watch}->measure(id=>"find best path");
    my ($paths, $scores) = ($self->{bestk} == 1) ? 
	$self->findBestPath($node, $link, $state) : 
	$self->findKthBestPath($node,$link,$state,$self->{bestk});
    $self->{watch}->stop;
    $self->{watch}->show if ($self->{debug});
    my @candidates;
    for my $path (@{$paths}) {
	push(@candidates,$self->getConvertedString($path));
    }
    return \@candidates,$scores;
}

sub convertForLinkCount {
    my ($self, %args) = @_;
    my $input = $args{input};
    utf8::decode($input);
    $self->{last_id} = $self->getMaxUnivID();
    my ($node, $link, $state) = $self->createGraphCount($input);
    my ($paths,$scores) = $self->findBestPath($node,$link,$state);
    return [$self->getConvertedString($paths->[0])], $scores;
}

sub getMaxUnivID {
    my $self = shift;
    my $sth = $self->{dbh}->prepare("select max(id) from word");
    $sth->execute();
    if (my @row = $sth->fetchrow) {
        return $row[0];
    }
    return undef;
}

sub generateNewChunk {
    my ($self, $surface) = @_;
    $self->{last_id}++;
    utf8::encode($surface);
    my $ch = $self->getChunk($self->{last_id},2964,2964,0,0,$surface);
    print STDERR "new word: $surface\n" if ($self->{debug});
    return $ch;
}

sub getChunk {
    my ($self, $id, $left_id, $right_id, $score, $kanji_id, $kanji) = @_;
    return {id => $id, 
	    left_id => $left_id, 
	    right_id => $right_id, 
	    score => $score, 
	    kanji_id => $kanji_id, 
	    kanji => $kanji};
}

sub createGraph {
    my ($self, $q) = @_;
    my ($node, $state) = $self->createNode($q);
    my $link = $self->createLink($state);
    return $node, $link, $state;
}

sub createGraphDebug {
    my ($self, $q) = @_;
    $self->{watch}->measure(id=>"create node");
    my ($node, $state) = $self->createNode($q);
    $self->{watch}->measure(id=>"create link");
    my $link = $self->createLink($state);
    $self->{watch}->stop;
    return $node, $link, $state;
}

sub createGraphCount {
    my ($self, $q) = @_;
    my ($node, $state) = $self->createNode($q);
    my $link = $self->createLinkCount($state);
    return $node, $link, $state;
}

sub createNode {
    my ($self, $q) = @_;
    my $agent = new marisa::Agent;
    my @state = ({0=>1},{});
    my %node; # $node{NODE_ID} = CHUNK_INFORMATION, NODE_ID := STATE_INDEX.CHUNK_ID
    my $sth_w = $self->{dbh}->prepare("select id,left_id,right_id,score,kanji_id,kanji from word where trie_id = ? limit 1000");
    $self->{chunk}{0} = $self->getChunk(0, 0, 0, 0, 0, '');
    $node{"0.$bos"} = $self->{chunk}{$bos};
    for (my $i = 1; $i < length($q)+1; $i++) {
	next if (!defined($state[$i]));
	my $substr = substr($q,$i-1,length($q));
	$agent->set_query(Encode::encode('utf8',$substr));
	while ($self->{trie}->common_prefix_search($agent)) {
	    my $key = $agent->key();
	    my $w = $key->str();
	    my $next_idx = $i+length(Encode::decode('utf8',$w));
	    my $trie_id = $key->id();
	    $sth_w->execute($trie_id);
	    while (my @row = $sth_w->fetchrow) {
		my $id = $row[0];
		$self->{chunk}{$id} = $self->getChunk(@row);
		$state[$i]->{$id} = $next_idx;
		$node{"$i.$id"} = $self->{chunk}{$id};
		$state[$next_idx] = {} if (!defined($state[$next_idx]));
	    }
	}
	#辞書にない場合 & それ以外に候補も無い場合
	if (scalar(keys %{$state[$i]}) == 0 && $i == $#state) {
	    $self->{chunk}{$self->{last_id}} = $self->generateNewChunk(substr($q,$i-1,1));
	    my $id = $self->{last_id};
	    my $next_idx = $i+1;
	    $state[$i]->{$id} = $next_idx;
	    $node{"$i.$id"} = $self->{chunk}{$id};
	    $state[$next_idx] = {} if (!defined($state[$next_idx]));
	}
    }
    my $last_idx = length($q)+1;
    $state[$last_idx]->{$eos} = 0;
    $node{"$last_idx.$eos"} = $self->{chunk}{$eos};
    return \%node,\@state;
}

sub createLink {
    my ($self,$state) = @_;
    my %link_rev; #$link_rev{TARGET_NODE_ID}{SOURCE_NODE_ID} = TRANSITION_SCORE
    my $sth_l = $self->{dbh}->prepare("select score from link where id1 = ? and id2 = ? limit 1");
    for (my $i = 0; $i < @{$state}-1; $i++) {
	for my $id (keys %{$state->[$i]}) {
	    my $id_r = $self->{chunk}{$id}{right_id};
	    my $pointer = $state->[$i]->{$id};
	    for my $id2 (keys %{$state->[$pointer]}) {
		my $id_l = $self->{chunk}{$id2}{left_id};
		if (!$self->{trans}{$id_r}{$id_l}) {
		    $sth_l->execute($id_r,$id_l);
		    my @row = $sth_l->fetchrow;
		    $self->{trans}{$id_r}{$id_l} = $row[0];
		}
		$link_rev{"$pointer.$id2"}{"$i.$id"} = $self->{trans}{$id_r}{$id_l};
	    }
	}
    }
    return \%link_rev;
}

sub createLinkCount {
    my ($self,$state) = @_;
    my %link_rev; #$link_rev{TARGET_NODE_ID}{SOURCE_NODE_ID} = TRANSITION_SCORE
    my $sth_l = $self->{dbh}->prepare("select score from link where id1 = ? and id2 = ? limit 1");
    for (my $i = 0; $i < @{$state}-1; $i++) {
        for my $id (keys %{$state->[$i]}) {
            my $id_r = $self->{chunk}{$id}{right_id};
            my $pointer = $state->[$i]->{$id};
            for my $id2 (keys %{$state->[$pointer]}) {
                my $id_l = $self->{chunk}{$id2}{left_id};
                if (!$self->{trans}{$id_r}{$id_l}) {
                    $sth_l->execute($id_r,$id_l);
                    my @row = $sth_l->fetchrow;
                    $self->{trans}{$id_r}{$id_l} = $row[0];
                }
                $link_rev{"$pointer.$id2"}{"$i.$id"} = $self->{trans}{$id_r}{$id_l};
		$self->{trans_count}{$id_r.",".$id_l}++;
            }
        }
    }
    return \%link_rev;
}

sub findBestPath {
    my ($self, $node, $link, $state) = @_;
    my %bp; #back pointer; $bp{NODE_ID} = SOURCE_NODE_ID
    my %score; #$score{NODE_ID} = EMISSION_SCORE + ΣSCORE
    $score{"0.$bos"} = $node->{"0.$bos"}{score};
    for (my $i = 1; $i < @{$state}; $i++) {
	for my $id (keys %{$state->[$i]}) {
	    my $s_min = 1000000000;
	    my $es_min = $s_min;
	    my $target_id = "$i.$id";
	    for my $source_id (keys %{$link->{$target_id}}) {
		my $trans_s = $link->{$target_id}{$source_id};
		my $emiss_s = $score{$source_id};
		if ($s_min > $trans_s + $emiss_s) {
		    $bp{$target_id} = $source_id;
		    $s_min = $trans_s + $emiss_s;
		    $es_min = $emiss_s;
		}
	    }
	    $score{$target_id} = $s_min + $node->{$target_id}{score};
	}
    }
    my $path = $self->decodePath(\%bp,$#{$state},$node);
    return [$path], [$score{"$#{$state}.$eos"}];
}

sub findKthBestPath {
    my ($self, $node, $link, $state, $k) = @_;
    my %dist;
    my %visited;
    my %queue;
    my %link_forward;
    for my $id (keys %{$node}) {
	$dist{$id} = 1000000000;
	$visited{$id} = 0;
    }
    $dist{"$#$state.$eos"} = 0;
    $queue{"$#$state.$eos"} = 0;
    while (keys %queue) {
	my @keys = sort{$queue{$a} <=> $queue{$b}} keys %queue;
	my $target_id = shift(@keys);
	my $score_so_far = $queue{$target_id};
	delete($queue{$target_id});
	next if ($visited{$target_id});
	$visited{$target_id} = 1;
	for my $source_id (keys %{$link->{$target_id}}) {
	    my $t_score = $link->{$target_id}{$source_id};
	    $link_forward{$source_id}{$target_id} = $t_score;
	    my $e_score = $node->{$source_id}{score};
	    next if ($visited{$source_id});
	    if ($dist{$source_id} > $score_so_far + $t_score + $e_score) {
		$dist{$source_id} = $score_so_far + $t_score + $e_score;
		$queue{$source_id} = $dist{$source_id};
	    }
	}
    }
    my $count = 0; #paths
    my %queue_r;
    my @path_k;
    my @score_k;
    my %kpaths;
    $queue_r{"0.$bos"} = {distance => $dist{"0.$bos"}, path => {}};
    while (keys %queue_r) {
	my @keys = sort{$queue_r{$a}{distance} <=> $queue_r{$b}{distance}} keys %queue_r;
	my $source_id = shift(@keys);
	my $elm = $queue_r{$source_id};
	delete($queue_r{$source_id});
	my $val_sofar = $elm->{distance} - $dist{$source_id};
	my $path_sofar = $elm->{path};
	if ($source_id eq "$#$state.$eos") {
	    my $kpath = $self->decodeKanjiPath($path_sofar,$#{$state},$node);
	    if (!$kpaths{$kpath}) {
		$kpaths{$kpath} = 1;
		push(@path_k, $path_sofar);
		push(@score_k, $val_sofar);
		$count++;
		last if ($count > $k);
	    }
	    else {
		next;
	    }
	}
	for my $target_id (keys %{$link_forward{$source_id}}) {
	    my $trans_s = $link->{$target_id}{$source_id};
	    my $next_val = $val_sofar + $trans_s + $dist{$target_id} + $node->{$source_id}{score};
	    my %next_path = %{$path_sofar};
	    $next_path{$target_id} = $source_id;
	    $queue_r{$target_id} = {distance => $next_val, path => \%next_path};
	}
    }
    my @paths;
    for my $bp (@path_k) {
	push(@paths, $self->decodePath($bp,$#{$state},$node));
    }
    return \@paths,\@score_k;
}

sub decodePath {
    my ($self,$bp,$last_idx,$node) = @_;
    my $target_id = "$last_idx.$eos";
    my @path = ($eos);
    while (my $id = $bp->{$target_id}) {
	push(@path,$node->{$id}{id});
	$target_id = $id;
    }
    @path = reverse(@path);
    return \@path;
}

sub decodeKanjiPath {
    my ($self,$bp,$last_idx,$node) = @_;
    my $target_id = "$last_idx.$eos";
    my $kpath = "".$eos." ";
    while (my $id = $bp->{$target_id}) {
        $kpath .= $node->{$id}{kanji_id}." ";
        $target_id = $id;
    }
    return $kpath;
}

sub getConvertedString {
    my ($self,$path,$option) = @_;
    $option = 0 if (!defined($option));
    my @str;
    shift @{$path}; #remove bos
    pop @{$path}; #remove eos
    for my $id (@{$path}) {
	push(@str,$self->{chunk}{$id}{kanji});
    }
    my $separator = "";
    $separator = "|" if ($option==1);
    return join($separator,@str);
}

1;
