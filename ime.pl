#!/usr/bin/perl
use strict;
use warnings;
use IMEJP;

my $conf_file = 'conf.perl';
my $conf = do $conf_file or die "$!$@";
my $ime = new IMEJP(trie_file => $conf->{trie_file}, 
		    database_file => $conf->{database_file},
		    cache_file => $conf->{connection_cache_file},
		    debug => $conf->{ime_debug});

my $input;
while ($input = <STDIN>) {
    chomp($input);
    print $ime->convert(input=>$input),"\n";
}
