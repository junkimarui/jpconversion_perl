#!/usr/bin/perl 
use strict;
use warnings;
use marisa;
use DBI;

my $conf_file = 'conf.perl';
my $conf = do $conf_file or die "$!$@";

my $dir = $conf->{dictionary_dir};
my $additional = $conf->{additional_dictionary};
my $connection_filename = $conf->{connection_filename};
my $filename = $conf->{trie_file};
my $database = $conf->{database_file};
my $sqlite = $conf->{sqlite};
my $trie = new marisa::Trie;
my $trie_kanji = new marisa::Trie;
my $temp = $conf->{temporary_file};
my $temp_trie_file = $conf->{temporary_trie_file};

my @dictfiles;
for (my $i = 0; $i < 9; $i++) {
    push(@dictfiles,"$dir/dictionary0$i.txt");
}
push(@dictfiles, $additional) if (defined($additional));

create_trie($filename,\@dictfiles);
#$trie->load($filename);

create_database($database,\@dictfiles,"$dir/$connection_filename");

sub create_trie {
    my $savefile = shift;
    my $dictfiles = shift;
    my $keyset = new marisa::Keyset;
    my $keyset_k = new marisa::Keyset;
    for my $dictfile (@{$dictfiles}) {
	open (my $dic, "<", "$dictfile") or die "can't open dictionary text: $!";
	while (my $line = <$dic>) {
	    chomp($line);
	    my ($kana, $s1, $s2, $s3, $kanji) = split("\t",$line);
	    $keyset->push_back($kana);
	    $keyset_k->push_back($kanji);
	}
	close($dic);
    }
    $trie->build($keyset);
    $trie->save($filename);
    $trie_kanji->build($keyset_k);
    $trie_kanji->save($temp_trie_file);
}

sub create_database {
    my $dbfile = shift;
    my $dictfiles = shift;
    my $connection_file = shift;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile");
    $dbh->do("drop table if exists word");
    $dbh->do("drop table if exists link");
    $dbh->do("create table word (id integer, trie_id integer, left_id integer, right_id integer, score integer, kanji_id integer, kanji text)");
    $dbh->do("create table link (id1 integer, id2 integer, score integer)");
    $dbh->do("create index trie_ind on word(trie_id)");
    $dbh->do("create unique index ids_ind on link(id1,id2)");
    my $agent = new marisa::Agent;
    my $sth_w = $dbh->prepare("insert into word(id,trie_id,left_id,right_id,score,kanji_id,kanji) values (?,?,?,?,?,?,?)");
    open (my $out, ">", $temp) or die "can't open temporary file: $!";
    my $id_univ = 1;
    for my $dictfile (@{$dictfiles}) {
        open (my $fh_dic, "<", "$dictfile") or die "can't open dictionary text: $!";
        while (my $line = <$fh_dic>) {
            chomp($line);
            my ($kana, $il, $ir, $score, $kanji) = split("\t",$line);
            $agent->set_query($kana);
	    $trie->lookup($agent);
	    my $trie_id = $agent->key()->id();
	    $agent->set_query($kanji);
	    $trie_kanji->lookup($agent);
	    my $kanji_id = $agent->key()->id();
	    if ($kanji !~ / /) {
		print $out "$id_univ $trie_id $il $ir $score $kanji_id $kanji","\n";
	    }
	    else {
		$sth_w->execute($id_univ,$trie_id,$il,$ir,$score,$kanji_id,$kanji);
	    }
	    $id_univ++;
        }
        close($fh_dic);
    }
    close($out);
    print STDERR "importing word file\n";
    system("$sqlite -separator ' ' $dbfile \".import $temp word\"");

    open ($out, ">", $temp) or die "can't open temporary file: $!";
    open (my $fh_cn, "<", "$connection_file") or die "can't open connection file : $!";
    my $count = 0;
    while (my $line = <$fh_cn>) {
	$count++;
	next if ($count == 1);
	print $out $line;
    }
    close($fh_cn);
    close($out);
    print STDERR "importing link file\n";
    system("$sqlite -separator ' ' $dbfile \".import $temp link\"");
    $dbh->disconnect();
    system("rm $temp");
}

