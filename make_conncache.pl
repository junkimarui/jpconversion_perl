#!/usr/bin/perl
use strict;
use warnings;
use IMEJP;

my $conf_file = 'conf.perl';
my $conf = do $conf_file or die "$!$@";
my $ime = new IMEJP(trie_file => $conf->{trie_file},
                    database_file => $conf->{database_file});

my $input;
while ($input = <STDIN>) {
    chomp($input);
    print STDERR $ime->convertForLinkCount(input=>$input),"\n";
}

my $conncount = $ime->{trans_count};
my $count = 0;
open (my $cache_fh,">",$conf->{connection_cache_file}) or die "$!:$@";
for my $conn (sort {$conncount->{$b} <=> $conncount->{$a}} keys %{$conncount}) {
    my ($id1, $id2) = split(",",$conn);
    print $cache_fh $id1,",", $id2,",",$ime->{trans}{$id1}{$id2},",",$conncount->{$conn},"\n";
    $count++;
}
close($cache_fh);
print STDERR "Connection Count:",$count,"\n";
