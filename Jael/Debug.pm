# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Debug;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Readonly;
use threads;

my $machine_id;
my $machine_name;
my $starting_time;

our @EXPORT = qw($ENABLE_GRAPHVIEWER);

Readonly::Scalar our $ENABLE_GRAPHVIEWER => 1;

sub init {
    $machine_id = shift;
    $machine_name = shift;
	my ($s, $m) = gettimeofday();
	$starting_time = $s + $m/1000000;
    return;
}

sub msg {
    if (exists $ENV{JAEL_DEBUG}) {
        my $msg = shift;
        my $tid = threads->tid();
		my $time;
		if (defined $starting_time) {
			my ($s, $m) = gettimeofday();
			$time = $s + $m/1000000;
			$time -= $starting_time;
		} else {
			$time = '?';
		}
        print STDERR "$machine_id ($machine_name, tid=$tid) [time : $time]: $msg\n";
    }
    return;
}

sub die {
    my $msg = shift;
    die "$machine_id ($machine_name) : $msg\n";
}

1;
