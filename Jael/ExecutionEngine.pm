# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::ExecutionEngine;

use strict;
use warnings;
use Readonly;
use threads;
use threads::shared;
use List::Util qw/shuffle/;
use File::Temp qw/tempdir/;
use Cwd;

use Jael::ServerEngine;
use Jael::TasksParser;
use Jael::TasksStack;
use Jael::ForkSet;
use Jael::Message;
use Jael::Dht;
use Jael::VirtualTask;
use Jael::Paje;

# -----------------------------------------------------------------

# Signal handler for all threads in program !

sub catch_SIGUSR1 {
    Jael::Debug::msg("[ExecutionEngine]die by SIGUSR1");
    Jael::Paje::destroy_thread();

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

    my $steal_authorized :shared = 1;

    Jael::Debug::msg('[ExecutionEngine]creating a new execution engine');

    $self->{config} = $config;
    $self->{id} = $config->{id};
    $self->{machines} = $config->{machines};

    # Set machine number for global data in Dht module and current object
    Jael::Dht::set_machines_number(scalar @{$config->{machines}});

    # Configure parameters and structures
    $self->{max_threads} = detect_cores() unless defined $self->{max_threads};
    $self->{tasks_stack} = Jael::TasksStack->new();
    $self->{fork_set} = Jael::ForkSet->new();
    $self->{steal_authorized} = \$steal_authorized;

    # Init working directory
    if ($self->{id} == 0) {
        $self->{working_directory} = getcwd();
    } else {
        $self->{working_directory} = tempdir("/tmp/jael_" . $self->{id} . "_XXXXXX");
        chdir $self->{working_directory} or die "Unable to chdir !";
    }

    bless $self, $class;

    # Init network
    $self->{network} = Jael::ServerEngine->new($self);

    return $self;
}

sub get_tasks_stack {
    my $self = shift;
    return $self->{tasks_stack};
}

sub get_fork_set {
    my $self = shift;
    return $self->{fork_set};
}

sub get_steal_variable {
    my $self = shift;
    return $self->{steal_authorized};
}

sub get_id {
    my $self = shift;
    return $self->{id};
}

sub get_machines {
    my $self = shift;
    return $self->{machines};
}

sub get_working_directory {
    my $self = shift;
    return $self->{working_directory};
}

sub compute_virtual_task {
    my $self = shift;
    my $task = shift;

    Jael::Debug::msg("[ExecutionEngine]get virtual task: " . $task->get_id() . " (sons: " .
                     @{$task->get_tasks_to_generate()} . ")");

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

                Jael::Debug::msg("[ExecutionEngine]task $task_id is requested");

                $self->{network}->send($destination, $message);
            } else {
                Jael::Debug::msg("[ExecutionEngine]task $task_id was already requested");
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
    my $task_id = $task->get_id();

    Jael::Debug::msg("[ExecutionEngine]get real task: " . $task_id . " and execute cmd");

    # Execute real task & update dependencies
    my $main_task_completed = $task->execute();
	Jael::Debug::msg("[ExecutionEngine] completed task '$task_id'");

    # TMP
    `touch $task_id`;

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
        # Send end message to all machines (except 0 and current process)
        my $message = Jael::Message->new($Jael::Message::END_ALL);
        $self->{network}->broadcast_except($message, [0]);

        # Send the last file to first machine
        unless ($self->{id} == 0) {
            my $filename = $task->get_task_id();

            open(my $fh, '<', $filename) or die "Can't open file '$filename' : $!";
            my $content = do { local $/; <$fh> };
            close $fh;

            my $message = Jael::Message->new($Jael::Message::FILE, $filename, $content);

            $message->set_priority($Jael::ServerEngine::SENDING_PRIORITY_LOW);
            $self->{server}->send(0, $message);
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
                    lock($self->{steal_authorized});

                    if (${$self->{steal_authorized}}) {
                        my $machine_id = ${$self->{rand_machines}}[$self->{last_rand_machine}];

                        # Update the next machine for steal request
                        $self->{last_rand_machine} = $self->{last_rand_machine}++ % @{$self->{rand_machines}};
                        ${$self->{steal_authorized}} = 0;

                        $self->{network}->send($machine_id, Jael::Message->new($Jael::Message::STEAL_REQUEST));
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
    Jael::Debug::msg("[ExecutionEngine]creating " . $self->{max_threads} . " threads");

    #TODO: fix threads on cores ? (especially communication threads)
    for (1..$self->{max_threads}) {
        my $thr = threads->create(\&computation_thread, $self);
        Jael::Paje::create_thread($thr->tid());
    }

    $self->{network}->run();

    return;
}

sub bootstrap_system {
    my $self = shift;

    Jael::Debug::msg("[ExecutionEngine]initialization");
    Jael::Debug::msg("[ExecutionEngine]computing tasks graph");

    # Initialize and create tasks graph
    Jael::TasksParser::make();

    die "missing target" unless defined $self->{config}->{target};

    Jael::TasksGraph::set_main_target($self->{config}->{target});
    Jael::TasksGraph::generate_reverse_dependencies();
    #TODO: use macros to avoid extra debug costs
    Jael::TasksGraph::display() if exists $ENV{JAEL_DEBUG} and $Jael::Debug::ENABLE_GRAPHVIEWER;

    # Broadcast the graph to everyone and wait
    $self->{network}->broadcast(new Jael::Message($Jael::Message::TASKGRAPH, 'taskgraph', Jael::TasksGraph::serialize()));
    $self->{network}->wait_while_messages_exists();

    # Get initial task
    my $init_task_id = Jael::TasksGraph::get_init_task_id();
    my $init_task = Jael::TasksGraph::get_task($init_task_id);

    Jael::Debug::msg("[ExecutionEngine]put initial task on stack: '$init_task_id'");

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
    Jael::Debug::msg("[ExecutionEngine]detected $count cores");

    return $count;
}

1;
