package Jael::ExecutionEngine;

use strict;
use warnings;
use threads;
use Jael::ServerEngine;
use Jael::TaskParser;
use Jael::Stack;
use Jael::Message;

#if enough ready tasks for everyone, work
#if enough ready tasks but some files are missing, wait for incoming files
#if not enough ready tasks, steal one task (TODO: good choice to steal only one ?)

sub new {
	my $class = shift;
	my $self = {};
	my $config = shift;
	Jael::Debug::msg('creating a new execution engine');
	$self->{id} = $config->{'id'};
	$self->{machines} = $config->{'machines'};
	$self->{machines_number} = @{$config->{'machines'}};
	#$self->{max_threads} = shift; TODO
	$self->{max_threads} = detect_cores() unless defined $self->{max_threads};
	$self->{active_threads} = 0;
	$self->{stack} = new Jael::Stack;
	$self->{network} = new Jael::ServerEngine($config->{'id'}, @{$config->{'machines'}}) if @{$config->{'machines'}} > 1;
	bless $self, $class;
	return $self;
}

sub start_server {
	my $self = shift;
	return unless @{$self->{machines}} > 1;
	$self->{network}->run();
}

sub bootstrap_system {
	my $self = shift;
	Jael::Debug::msg("initialisation");
	Jael::Debug::msg("computing tasks graph");
	my $graph = Jael::TaskParser::make();
	#$graph->set_main_target('/home/wagnerf/code/jael/bin/test3');
	#$graph->generate_virtual_tasks();
	#$graph->display_graph() if exists $ENV{JAEL_DEBUG};
	$self->{taskgraph} = $graph;
	#now, if there is a network, broadcast the graph to everyone
	if (defined $self->{network}) {
		$self->{network}->broadcast(new Jael::Message(TASKGRAPH, 'taskgraph', "$self->{taskgraph}"));
	}
	#put initial task on the stack
	die 'TODO put init task';
}

sub detect_cores {
	my $os = `uname`;
	chomp($os);
	return 1 unless $os eq 'Linux';
	open(PROC, '< /proc/cpuinfo') or return 1;
	my $count = 0;
	while(<PROC>) {
		$count++ if /^processor\s+:\s+\d+/;
	}
	close(PROC);
	Jael::Debug::msg("detected $count cores");
	return $count;
}

1;
