package IMEJP;
use strict;
use warnings;
use marisa;
use Encode;
use DBI;
use StopWatch;

our $bos = 0;
our $eos = 0;

sub new {
    my ($class, %args) = @_;
    my $self = {};
    bless($self, $class);
    $self->{chunk} = {};
    $self->{trans} = {};
    $self->{trie} = new marisa::Trie;
    $self->{trie}->load($args{trie_file});
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$args{database_file}") or die "Can't open database $!";
    $self->{last_id} = 0;
    $self->{debug} = $args{debug};
    $self->{debug} = 0 if (!defined($self->{debug}));
    return $self;
}

sub convert {
    my ($self, %args) = @_;
    my $input = $args{input};
    utf8::decode($input);
    $self->{watch} = new StopWatch;
    $self->{last_id} = $self->getMaxUnivID();
    my ($node, $link, $state) = $self->createGraph($input);
    $self->{watch}->measure(id=>"find best path");
    my $path = $self->findBestPath($node,$link,$state);
    $self->{watch}->stop;
    $self->{watch}->show if ($self->{debug});
    return $self->getConvertedString($path);
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
    my $ch = $self->getChunk($self->{last_id},2964,2964,0,$surface);
    print STDERR "new word: $surface\n" if ($self->{debug});
    return $ch;
}

sub addNode {
    my ($self,$node,$state,$ch,$i,$next_idx,$pointer) = @_;
    my $id = $ch->{id}; 
    push(@{$state->[$i]},$id);
    $node->{"$i.$id"} = $ch;
    $state->[$next_idx] = [] if (!defined($state->[$next_idx]));
    $pointer->{"$i.$id"} = $next_idx;
}

sub getChunk {
    my ($self, $id, $left_id, $right_id, $score, $kanji) = @_;
    return {id => $id, left_id => $left_id, right_id => $right_id, score => $score, kanji => $kanji};
}

sub createGraph {
    my ($self, $q) = @_;
    my $agent = new marisa::Agent;
    my @state = ([$bos],[]);
    my %node; # $node{NODE_ID} = CHUNK_INFORMATION, NODE_ID := STATE_INDEX.CHUNK_ID
    my %pointer = ("0.$bos"=>1); #pointer{NODE_ID} = next_idx
    my $sth_w = $self->{dbh}->prepare("select id,left_id,right_id,score,kanji from word where trie_id = ? limit 1000");
    $self->{chunk}{0} = $self->getChunk(0, 0, 0, 0, '');
    $node{"0.$bos"} = $self->{chunk}{$bos};
    $self->{watch}->measure(id=>"create node");
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
		$self->{chunk}{$row[0]} = $self->getChunk(@row);
		$self->addNode(\%node,\@state,$self->{chunk}{$row[0]},$i,$next_idx,\%pointer);
	    }
	}
	#辞書にない場合 & それ以外に候補も無い場合
	if (scalar(@{$state[$i]}) == 0 && $i == $#state) {
	    $self->{chunk}{$self->{last_id}} = $self->generateNewChunk(substr($q,$i-1,1));
	    my $next_idx = $i+1;
	    $self->addNode(\%node,\@state,$self->{chunk}{$self->{last_id}},$i,$next_idx,\%pointer);
	}
    }
    $self->{watch}->stop;
    my $last_idx = length($q)+1;
    $state[$last_idx] = [$eos];
    $pointer{"$last_idx.$eos"} = 0;
    $node{"$last_idx.$eos"} = $self->{chunk}{$eos};
    $self->{watch}->measure(id=>"create link");
    my $link = $self->createLink(\@state,\%pointer,scalar(keys(%node)));
    $self->{watch}->stop;
    return \%node,$link,\@state;
}

sub createLink {
    my ($self,$state,$pointer,$node_count) = @_;
    my %link_rev; #$link_rev{TARGET_NODE_ID}{SOURCE_NODE_ID} = TRANSITION_SCORE
    my $sth_l = $self->{dbh}->prepare("select score from link where id1 = ? and id2 = ? limit 1");
    keys(%link_rev) = $node_count;
    for (my $i = 0; $i < @{$state}-1; $i++) {
	for my $id (@{$state->[$i]}) {
	    keys(%{$link_rev{"$i.$id"}}) = 30;
	}
    }
    for (my $i = 0; $i < @{$state}-1; $i++) {
	for my $id (@{$state->[$i]}) {
	    my $id_r = $self->{chunk}{$id}{right_id};
	    my $ptr = $pointer->{"$i.$id"};
	    for my $id2 (@{$state->[$ptr]}) {
		my $id_l = $self->{chunk}{$id2}{left_id};
		if (!$self->{trans}{$id_r.",".$id_l}) {
		    $sth_l->execute($id_r,$id_l);
		    my @row = $sth_l->fetchrow;
		    $self->{trans}{$id_r.",".$id_l} = $row[0];
		}
		$link_rev{"$ptr.$id2"}{"$i.$id"} = $self->{trans}{$id_r.",".$id_l};
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
	for my $id (@{$state->[$i]}) {
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
    my @path = ($eos);
    my $target_id = "$#{$state}.$eos";
    while (my $id = $bp{$target_id}) {
	push(@path,$node->{$id}{id});
	$target_id = $id;
    }
    @path = reverse(@path);
    return \@path;
}

sub findKthBestPath {
    my ($self, $node, $link, $state, $k) = @_;
    my %dist;
    
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
