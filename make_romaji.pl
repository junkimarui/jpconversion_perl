#!/usr/bin/perl
use strict;
use warnings;
use marisa;

my $conf_file = 'conf.perl';
my $conf = do $conf_file or die "$!$@";
my $romaji_file = $conf->{romaji_file};
my $romaji_trie = $conf->{romaji_trie};

my $keyset = new marisa::Keyset;
open (my $fh, "<", $romaji_file);
while (my $l = <$fh>) {
    chomp($l);
    my @row = split("\t",$l);
    $keyset->push_back($row[0]);
}
close($fh);

my $trie = new marisa::Trie;
$trie->build($keyset);
$trie->save($romaji_trie);
