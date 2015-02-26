# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
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
    $self->{config} = $config;
    $self->{id} = $config->{'id'};
    $self->{machines} = $config->{'machines'};
    $self->{machines_number} = @{$config->{'machines'}};
    #$self->{max_threads} = shift; TODO
    $self->{max_threads} = detect_cores() unless defined $self->{max_threads};
    $self->{active_threads} = 0;
    $self->{stack} = Jael::Stack->new();
    $self->{network} = new Jael::ServerEngine($config->{'id'}, @{$config->{'machines'}}) if @{$config->{'machines'}} > 1;
    
    bless $self, $class;
    
    return $self;
}

#TODO a faire : code des threads de calcul

sub computation_thread {
    my $self = shift; # Protocol engine
    
    while(1) {
        # Take task
        my $task = $self->{stack}->pop_value();

        # Steal
        if(not defined $task) {
            sleep(0.2);
        } elsif($task->get_id() =~ /^virtual\/\//) {

        } else {

        }
    }

    return;
}

sub start_server {
    my $self = shift;

    # Make threads for computation
    # It's not needed to wait the end thread (infinite loop)
    for my $i (0..$self->{max_threads}) {
        threads->create(\&computation_thread, $self);
    }
    
    $self->{network}->run() if @{$self->{machines}} > 1;
    
    return;
}

sub bootstrap_system {
    my $self = shift;
    Jael::Debug::msg("initialisation");
    Jael::Debug::msg("computing tasks graph");

    my $graph = Jael::TaskParser::make();
    
    die "missing target" unless defined $self->{config}->{target};
    
    $graph->set_main_target($self->{config}->{target});
    $graph->generate_virtual_tasks();
    $graph->display_graph() if exists $ENV{JAEL_DEBUG};
        
    $self->{taskgraph} = $graph;
    
    # Now, if there is a network, broadcast the graph to everyone
    if (defined $self->{network}) {
        $self->{network}->broadcast(new Jael::Message(TASKGRAPH, 'taskgraph', "$self->{taskgraph}"));
    }

    die;
    
    # Put initial task on the stack
    Jael::Debug::msg("put initial task on task: " . $self->{config}->{target});
    #$self->{stack}->push_value
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
