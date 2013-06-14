package RomajiConverter;
use strict;
use warnings;
use marisa;

sub new {
    my ($class, %args) = @_;
    my $self = {};
    bless($self, $class);
    $self->{trie} = new marisa::Trie;
    $self->{trie}->load($args{romaji_trie}) ;
    my $table_file = $args{romaji_file};
    $self->{table} = readRomajiFile($table_file);
    $self->{escape} = $args{escape_character}//'\\$';
    return $self;
}

sub readRomajiFile {
    my %table;
    open(my $fh, "<", shift) or die "can't read Romaji File:%!\n";
    while (my $l = <$fh>) {
	chomp($l);
	my ($romaji, $kana) = split("\t",$l);
	$table{$romaji} = $kana;
    }
    return \%table;
}

sub convert {
    my ($self, %args) = @_;
    my $input = $args{input};
    my $i = 0;
    my $str = "";
    my $esc_flag = 0;
    my $esc = $self->{escape};
    my $agent = new marisa::Agent;
    while ($i < length($input)) {
	my $substr = substr($input,$i,length($input));
	if ($substr =~ /^$esc/) {
	    if ($esc_flag) {
		$esc_flag = 0;
	    }
	    else {
		$esc_flag = 1;
	    }
	    ++$i; next;
	}
	my $elm = substr($input,$i,1);
	if ($esc_flag) {
	    $str .= $elm;
	}
	else {
	    $agent->set_query($substr);
	    while ($self->{trie}->common_prefix_search($agent)) {  
		$elm = $agent->key()->str();
	    }
	    $str .= $self->{table}{$elm} // $elm;
	}
	$i += length($elm);
    }
    return $str;
}

1;
