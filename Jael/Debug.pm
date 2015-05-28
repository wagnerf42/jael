# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Debug;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Readonly;
use threads;
use Carp;

my $machine_id;
my $machine_name;
my $starting_time;

our @EXPORT = qw($ENABLE_GRAPHVIEWER);

my $ENABLE_GRAPHVIEWER = 0;

my %displayed_tags;

sub init {
    $machine_id = shift;
    $machine_name = shift;
	my ($s, $m) = gettimeofday();
	$starting_time = $s + $m/1000000;
    if (exists $ENV{JAEL_DEBUG}) {
		my @tags = split(':', $ENV{JAEL_DEBUG});
		$displayed_tags{$_} = 1 for @tags;
		print STDERR "$machine_id : logs are activated for @tags\n";
	}
    return;
}

sub enable_graph_viewer {
	$ENABLE_GRAPHVIEWER = 1;
	return;
}

sub logs_activated_for {
	my $tag = shift;
	return (defined $displayed_tags{$tag});
}

sub msg {
	my $tag = shift;
	my $msg = shift;
	confess 'missing tag' unless defined $tag;
	confess 'missing msg' unless defined $msg;
	return unless defined $displayed_tags{$tag};

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
	return;
}

sub die {
	my $msg = shift;
	die "$machine_id ($machine_name) : $msg\n";
}

1;
