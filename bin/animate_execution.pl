#!/usr/bin/env perl

use strict;
use warnings;
use Jael::TasksParser;

die 'needed_args: graph_log_file events_log_file' unless defined $ARGV[1] and -f $ARGV[0] and -f $ARGV[1];

my $tasks = Jael::TasksParser::make($ARGV[0]);

my $events = parse_events($ARGV[1]);

my @colors = qw(red green blue brown gray violet yellow orange cyan coral chartreuse aliceblue beige dimgray blueviolet darkgoldenrod1 darkorange1 aquamarine1);

my $current_time;
for my $event (@$events) {
	my ($date, $thread_id, $task_id) = @$event;
	if (defined $current_time) {
		sleep($date - $current_time);
	} else {
		Jael::TasksGraph::display();
	}
	Jael::TasksGraph::colorize_task($task_id, $colors[$thread_id % @colors]) if defined $thread_id;
	Jael::TasksGraph::display();
	$current_time = $date;
}

sub parse_events {
	my $file = shift;
	my @events;
	open(my $fd, '<' , $file) or die "cannot open file $file";
	while(my $line=<$fd>) {
		if ($line =~/(\d+) \(\S+, tid=(\d+)\) \[time : (\d+(\.\d+)?(e-?\d+)?)\]: \[ExecutionEngine\] completed task '(.*)'/) {
			push @events, [$1, $3, $6];
		}
	}
	close($fd);
	return \@events;
}
