#!/usr/bin/perl
use strict;
use warnings;
use IMEJP;
use RomajiConverter;

my $conf_file = 'conf.perl';
my $conf = do $conf_file or die "$!$@";
my $ime = new IMEJP(trie_file => $conf->{trie_file}, 
		    database_file => $conf->{database_file},
		    cache_file => $conf->{connection_cache_file},
		    debug => $conf->{ime_debug},
		    bestk => $conf->{bestk});

my $input;
my $romaji = new RomajiConverter(romaji_trie => $conf->{romaji_trie}, romaji_file => $conf->{romaji_file});
while ($input = <STDIN>) {
    chomp($input);
    $input = $romaji->convert(input=>$input) if ($conf->{from_romaji});
    my ($cand,$score) = $ime->convert(input=>$input);
    for (my $i = 0; $i < @{$cand}; $i++) {
	print $cand->[$i];
	#スコアの表示
	if ($conf->{ime_debug}) {
	    print "(",$score->[$i],")\n";
	}
	else {
	    print "\n";
	}
    }
}
