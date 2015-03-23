# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::ExecutionEngine;

use strict;
use warnings;
use threads;

use Jael::ServerEngine;
use Jael::TasksParser;
use Jael::TasksStack;
use Jael::Message;
use Jael::Dht;
use Jael::VirtualTask;

# -----------------------------------------------------------------

# Signal handler for all threads in program !

sub catch_SIGUSR1 {
    Jael::Debug::msg("thread " . threads->tid() . " die");
    threads->exit();
    
    die "unreached";
}

$SIG{USR1} = \&catch_SIGUSR1;

# -----------------------------------------------------------------

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

    # Set machine number for global data in Dht module and current object
    $self->{machines_number} = @{$config->{'machines'}};
    Jael::Dht::set_machines_number($self->{machines_number});
        
    $self->{max_threads} = detect_cores() unless defined $self->{max_threads};
    $self->{active_threads} = 0;
    $self->{stack} = Jael::TasksStack->new();
    $self->{dht} = new Jael::Dht();
    $self->{network} = new Jael::ServerEngine($self->{dht}, $config->{'id'}, @{$config->{'machines'}});
    
    bless $self, $class;
    
    return $self;
}

sub computation_thread {
    my $self = shift; # Protocol engine
    my $tid = threads->tid();

    while(1) {
        # Take task
        my $task = $self->{stack}->pop_task();

        # No tasks
        if(not defined $task) {
            sleep(0.2);
        } 

        # Virtual task
        elsif($task->is_virtual()) {
            Jael::Debug::msg("tid $tid get virtual task: " . $task->get_id() . " (sons: " . @{$task->get_tasks_to_generate()} . ")");

            # Get tasks to generate
            my $tasks = $task->get_tasks_to_generate(); 

            # For each task, we send to DHT_OWNER($task) : 'We have $task on our stack'
            for $task (@{$tasks}) {
                my $message = Jael::Message->new(TASK_IS_PUSHED, $task->get_id());
                my $destination = Jael::Dht::hash_task_id($task->get_id(), $self->{machines_number});

                # Send to DHT_OWNER($task)
                $self->{network}->send($destination, $message);
            }

            # Push tasks in stack
            $self->{stack}->push_task(@$tasks);
        } 

        # Real task
        else {
            Jael::Debug::msg("tid $tid get real task: " . $task->get_id());

            # Execute real task & update dependencies
            Jael::Debug::msg("tid $tid execute cmd");
            my $main_task_completed = $task->execute();

            # TODO: Check if execute returns error !
            
            # Protocol end
            # Send message to the first process/machine
            if ($main_task_completed) {
                my $message = Jael::Message->new(END_ALL);
                $self->{network}->send(0, $message);
            } 

            # We send to DHT_OWNER($task) : 'I computed $task' and local dependencies update
            else {
                my $message = Jael::Message->new(TASK_COMPUTATION_COMPLETED, $task->get_id());
                my $destination = Jael::Dht::hash_task_id($task->get_id(), $self->{machines_number});

                # Send to DHT_OWNER($task)
                $self->{network}->send($destination, $message);
                $self->{stack}->update_dependencies($task->get_id());                
            }
        }
    }

    return;
}

sub start_server {
    my $self = shift;
    # Make threads for computation
    # It's not needed to wait the end thread (infinite loop)
    Jael::Debug::msg("creating " . $self->{max_threads} . " threads");
    
    for my $i (1..$self->{max_threads}) {
        threads->create(\&computation_thread, $self);
    }
    
    $self->{network}->run();
    
    return;
}

sub bootstrap_system {
    my $self = shift;
    
    Jael::Debug::msg("initialization");
    Jael::Debug::msg("computing tasks graph");

    # Initialize and create tasks graph
    Jael::TasksParser::make();
    
    die "missing target" unless defined $self->{config}->{target};
    
    Jael::TasksGraph::set_main_target($self->{config}->{target});
    Jael::TasksGraph::generate_reverse_dependencies();
    Jael::TasksGraph::display() if exists $ENV{JAEL_DEBUG};
            
    # Broadcast the graph to everyone
    # TODO : Send properly tasks graph
    #$self->{network}->broadcast(new Jael::Message(TASKGRAPH, 'taskgraph', $taskgraph));

    # Get initial task
    my $init_task_id = $VIRTUAL_TASK_PREFIX . Jael::TasksGraph::get_main_target();
    my $init_task = Jael::TasksGraph::get_task($init_task_id);

    Jael::Debug::msg("put initial task on task: '$init_task_id'");

    # We send to DHT_OWNER($task) : 'We have $task on our stack'
    my $message = Jael::Message->new(TASK_IS_PUSHED, $init_task->get_id());
    my $destination = Jael::Dht::hash_task_id($init_task->get_id());

    # Send to DHT_OWNER($task)
    $self->{network}->send($destination, $message);
        
    # Put initial task on the stack
    $self->{stack}->push_task($init_task);

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
