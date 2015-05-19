# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::ExecutionEngine;

use strict;
use warnings;
use Readonly;
use threads;
use threads::shared;
use List::Util qw/shuffle/;

use Jael::ServerEngine;
use Jael::TasksParser;
use Jael::TasksStack;
use Jael::ForkSet;
use Jael::Message;
use Jael::Dht;
use Jael::VirtualTask;

# -----------------------------------------------------------------

# Signal handler for all threads in program !

sub catch_SIGUSR1 {
    Jael::Debug::msg("die by SIGUSR1");
    threads->exit();

    die "unreached";
}

$SIG{USR1} = \&catch_SIGUSR1;

# -----------------------------------------------------------------

# TODO
#if enough ready tasks for everyone, work
#if enough ready tasks but some files are missing, wait for incoming files
#if not enough ready tasks, steal one task (TODO: good choice to steal only one ?)

sub new {
    my $class = shift;
    my $self = {};
    my $config = shift;

    my $steal_activated :shared = 1;

    Jael::Debug::msg('creating a new execution engine');

    $self->{config} = $config;
    $self->{id} = $config->{id};
    $self->{machines} = $config->{machines};

    # Set machine number for global data in Dht module and current object
    Jael::Dht::set_machines_number(scalar @{$config->{'machines'}});

    $self->{max_threads} = detect_cores() unless defined $self->{max_threads};
    $self->{tasks_stack} = Jael::TasksStack->new();
    $self->{fork_set} = Jael::ForkSet->new();
    $self->{steal_activated} = \$steal_activated;
    $self->{network} = Jael::ServerEngine->new($self->{tasks_stack}, $self->{fork_set}, $self->{steal_activated},
                                               $config->{id}, $config->{machines});

    bless $self, $class;

    return $self;
}

sub compute_virtual_task {
    my $self = shift;
    my $task = shift;

    Jael::Debug::msg("get virtual task: " . $task->get_id() . " (sons: " . @{$task->get_tasks_to_generate()} . ")");

    # Get tasks to generate
    my $tasks_ids = $task->get_tasks_to_generate();
    my @tasks;

    for my $task_id (@{$tasks_ids}) {
        # For each real task, we send to DHT_OWNER($task) : 'We have $task on our stack'
        unless ($task_id =~ /^$VIRTUAL_TASK_PREFIX/) {
            my $message = Jael::Message->new($Jael::Message::TASK_IS_PUSHED, $task_id);
            my $destination = Jael::Dht::hash_task_id($task_id);

            $self->{network}->send($destination, $message);
        } elsif (Jael::TasksGraph::task_must_be_forked($task_id)) {
            # check if The task was not already requested by the process
            if ($self->{fork_set}->set_wait_status($task_id) != -1) {
                my $message = Jael::Message->new($Jael::Message::FORK_REQUEST, $task_id);
                my $destination = Jael::Dht::hash_task_id($task_id);

                Jael::Debug::msg("task $task_id is requested");

                $self->{network}->send($destination, $message);
            } else {
                Jael::Debug::msg("task $task_id was already requested");
            }

            # Don't push directly one potential virtual forked task
            next;
        }

        push @tasks, Jael::TasksGraph::get_task($task_id);
    }

    # Push tasks in stack
    $self->{tasks_stack}->push_task(@tasks);

    return;
}

sub compute_real_task {
    my $self = shift;
    my $task = shift;

    Jael::Debug::msg("get real task: " . $task->get_id() . " and execute cmd");

    # Execute real task & update dependencies
    my $main_task_completed = $task->execute();

    # TODO: Check if execute returns error !

    # We send to DHT_OWNER($task) : 'I computed $task' and local dependencies update
    unless ($main_task_completed) {
        my $message = Jael::Message->new($Jael::Message::TASK_COMPUTATION_COMPLETED, $task->get_id());
        my $destination = Jael::Dht::hash_task_id($task->get_id());

        # Send to DHT_OWNER($task)
        $self->{network}->send($destination, $message);
        $self->{tasks_stack}->update_dependencies($task->get_id());
    }
    # Protocol end
    else {
        # Send end message to all machines (except 0)
        my $message = Jael::Message->new($Jael::Message::END_ALL);
        $self->{network}->broadcast_except($message, [0]);

        # Send the last file to first machine
        unless ($self->{id} == 0) {
            # TODO
        }

        $self->{network}->wait_while_messages_exists();

        # Kill current process
        $self->{network}->send($self->{id}, $message);
    }

    return;
}

sub computation_thread {
    my $self = shift; # Protocol engine

    # Array of random machines for steal requests (no shared, one unique array by thread)
    # We remove the current machine id of the list
    $self->{rand_machines} = [grep {$_ ne $self->{id}} (0..@{$self->{machines}}-1)];
    $self->{rand_machines} = [shuffle(@{$self->{rand_machines}})];

    $self->{last_rand_machine} = 0;

    while (1) {
        # Take task
        my $task = $self->{tasks_stack}->pop_task();

        # No tasks
        if (not defined $task) {
            # No requests for fork => We can steal
            unless ($self->{fork_set}->get_requests_number()) {
                {
                    lock($self->{steal_activated});

                    if (${$self->{steal_activated}}) {
                        my $machine_id = ${$self->{rand_machines}}[$self->{last_rand_machine}];

                        # Update the next machine for steal request
                        $self->{last_rand_machine} = $self->{last_rand_machine}++ % @{$self->{rand_machines}};
                        #${$self->{steal_activated}} = 0;

                       # $self->{network}->send($machine_id, Jael::Message->new($Jael::Message::STEAL_REQUEST));
                    }
                }
            }

            sleep(1.0);
        }
        # Virtual task
        elsif ($task->is_virtual()) {
            compute_virtual_task($self, $task);
        }
        # Real task
        else {
            compute_real_task($self, $task);
        }
    }

    return;
}

sub start_server {
    my $self = shift;

    # Make threads for computation
    # It's not needed to wait the end thread (infinite loop)
    Jael::Debug::msg("creating " . $self->{max_threads} . " threads");

    #TODO: fix threads on cores ? (especially communication threads)
    for (1..$self->{max_threads}) {
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
    Jael::TasksGraph::display() if exists $ENV{JAEL_DEBUG} and $Jael::Debug::ENABLE_GRAPHVIEWER;

    # Broadcast the graph to everyone and wait
    $self->{network}->broadcast(new Jael::Message($Jael::Message::TASKGRAPH, 'taskgraph', Jael::TasksGraph::serialize()));
    $self->{network}->wait_while_messages_exists();

    # Get initial task
    my $init_task_id = Jael::TasksGraph::get_init_task_id();
    my $init_task = Jael::TasksGraph::get_task($init_task_id);

    Jael::Debug::msg("put initial task on stack: '$init_task_id'");

    # Put initial task on the stack
    $self->{tasks_stack}->push_task($init_task);

    return;
}

sub detect_cores {
    my $os = `uname`;
    chomp($os);
    return 1 unless $os eq 'Linux';

    open(my $proc, '<', '/proc/cpuinfo') or return 1;

    my $count = 0;

    while(<$proc>) {
        $count++ if /^processor\s+:\s+\d+/;
    }

    close($proc);
    Jael::Debug::msg("detected $count cores");

    return $count;
}

1;
