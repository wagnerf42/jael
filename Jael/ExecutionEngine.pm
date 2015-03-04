# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::ExecutionEngine;

use strict;
use warnings;

use threads;

use Jael::ServerEngine;
use Jael::TaskParser;
use Jael::TasksStack;
use Jael::Message;

use Jael::VirtualTask; # use VIRTUAL_TASK_PREFIX

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
    #$self->{max_threads} = 0;
    $self->{active_threads} = 0;
    $self->{stack} = Jael::TasksStack->new();
    $self->{network} = new Jael::ServerEngine($config->{'id'}, @{$config->{'machines'}}) if @{$config->{'machines'}} > 1;
    
    bless $self, $class;
    
    return $self;
}

sub get_tasks_to_generate_by_taskgraph {
    my $self = shift;
    my $task = shift;

    my @tasks = map {$self->{taskgraph}->{tasks}->{$_}} @{$task->get_tasks_to_generate()};

    return \@tasks;
}

sub computation_thread {
    my $self = shift; # Protocol engine
    my $virtual_reg = qr/${\(VIRTUAL_TASK_PREFIX)}/;
    my $tid = threads->tid();
    
    while(1) {
        # Take task
        my $task = $self->{stack}->pop_task();

        # No tasks
        if(not defined $task) {
            sleep(0.2);
        } 

        # Virtual task
        elsif($task->get_id() =~ $virtual_reg) {
            Jael::Debug::msg("tid $tid get virtual task: " . $task->get_id() . " (sons: " . @{$task->get_tasks_to_generate()} . ")");

            # Get tasks to generate & Push
            my $tasks = $self->get_tasks_to_generate_by_taskgraph($task);
            $self->{stack}->push_several_tasks($tasks);
        } 

        # Real task
        else {
            Jael::Debug::msg("tid $tid get real task: " . $task->get_id());

            # Execute real task & update dependencies
            my $cmd = $task->get_command();
        
            Jael::Debug::msg("tid $tid execute cmd");
            `$cmd`;

            $self->{stack}->update_dependencies($task->get_id());
        }
    }

    return;
}

sub start_server {
    my $self = shift;

    # It exists one network if it exists 2 machines or more
    if (@{$self->{machines}} > 1) {
        $self->{network}->run();
    } else {
        Jael::Debug::msg("no network: creating 1 computation thread");

        while (1) {
                        sleep(0.2);
        }
        computation_thread($self);
    }
    
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
    
    # Put initial task on the stack
    my $init_task = VIRTUAL_TASK_PREFIX . $graph->get_main_target();
    Jael::Debug::msg("put initial task on task: '$init_task'");
    
    $self->{stack}->push_task($graph->{tasks}->{$init_task});

    # Make threads for computation
    # It's not needed to wait the end thread (infinite loop)
    Jael::Debug::msg("creating " . $self->{max_threads} . " threads");
    
    for my $i (1..$self->{max_threads}) {
        threads->create(\&computation_thread, $self);
    }
    
    return;
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
