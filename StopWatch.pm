package StopWatch;

use strict;
use warnings;
use Time::HiRes;

sub new {
    my ($class, %args) = @_;
    my $self = {};
    bless($self, $class);
    $self->{series} = [];
    $self->{ids} = [];
    $self->{index} = {};
    $self->{lastest_time} = Time::HiRes::time;
    $self->{tmp_id} = "";
    return $self;
}

sub measure {
    my ($self, %args) = @_;
    $self->stop if ($self->{tmp_id} ne "");
    $self->{tmp_id} = $args{id};
    $self->{latest_time} = Time::HiRes::time;
}

sub stop {
    my ($self, %args) = @_;
    my $current = Time::HiRes::time;
    my $id = $self->{tmp_id};
    my $proc_time = $current - $self->{latest_time};
    if (defined($self->{index}{$id})) {
	my $idx = $self->{index}{$id};
	$self->{series}->[$idx] += $proc_time;
    }
    else {
	push(@{$self->{series}}, $proc_time);
	push(@{$self->{ids}}, $id);
	$self->{index}{$id} = $#{$self->{series}};
    }
}

sub show {
    my ($self, %args) = @_;
    for (my $i = 0; $i < @{$self->{series}}; $i++) {
	print $self->{ids}->[$i],":",$self->{series}->[$i],"sec\n";
    }
}

1;
