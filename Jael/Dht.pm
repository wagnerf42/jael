# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Dht;

use strict;
use warnings;

my $machines_number; #we need to know number of machines in hash function

# Make a new Dht, no parameters
sub new {
    my $class = shift;
    my $self = {};

    $self->{tasks_owners} = {}; # Update by TASK_IS_PUSHED
    $self->{task_status} = {};  # Update by TASK_COMPUTATION_COMPLETED and DEPENDENCIES_UPDATE_TASK_COMPLETED
    $self->{task_forked} = {};  # Update by FORK_REQUEST
    $self->{data_owners} = {};  # Update by TASK_COMPUTATION_COMPLETED

    bless $self, $class;

    return $self;
}

# Define the machines number on network
sub set_machines_number {
    die "machines number is already defined !" if defined $machines_number;
    $machines_number = shift;

    return;
}

# Get not unique identifier for one task id in [0..n_machines]
sub hash_task_id {
    my $task_id = shift;
    my $hash_value = 0;

    # TODO : Temp hash function... Test others functions

    for my $c (split //, $task_id) {
        $hash_value = ($hash_value << 5) | ($hash_value >> 27);
        $hash_value += ord($c);
    }

    return $hash_value % $machines_number;
}

# Set machine owning task, not the DHT_OWNER but the machine's stack using this task.
# careful : puts status to not ready
sub set_machine_owning {
    my $self = shift;
    my $task_id = shift;
    my $machine_id = shift;

    $self->{tasks_owners}->{$task_id} = $machine_id;
    $self->{task_status}->{$task_id} = $TASK_STATUS_NOT_READY;

    return;
}

# Update task's status
sub change_task_status {
    my $self = shift;
    my $task_id = shift;
    my $task_status = shift;

    $self->{task_status}->{$task_id} = $task_status;

    return;
}

# Fork request by one machine id for one task id
# Check and set fork status
sub fork_request {
    my $self = shift;
    my $task_id = shift;
    my $machine_id = shift;

    # Check if task is already forked
    return 0 if defined $self->{task_forked}->{$task_id};

    # The task is forked now
    $self->{task_forked}->{$task_id} = $machine_id;

    return 1;
}

# Compute the DHT_OWNERs of reverse depencies of one task id
sub compute_dht_owners_for_tasks_depending_on {
    my $self = shift;
    my $task_id = shift;

    # Get tasks depending on $task_id
    my $sons_task_id = Jael::TasksGraph::get_reverse_dependencies($task_id);

    my %owners;

    # Get owners
    for my $son_task_id (@{$sons_task_id}) {
        my $owner = hash_task_id($son_task_id);
        $owners{$owner} = 1;
    }

    return (keys %owners);
}

# Update the owners list of one task data
sub add_data_owner {
    my $self = shift;
    my $task_id = shift;
    my $machine_id = shift;

    push @{$self->{data_owners}->{$task_id}}, $machine_id;

    return;
}

# Return list of machines having data
sub get_data_owners {
    my $self = shift;
    my $task_id = shift;

    return [] if not defined $self->{data_owners}->{$task_id};
    return $self->{data_owners}->{$task_id};
}

# One task is now completed => Check if we can update the reverse dependencies to READY state
# Return the list of tasks which turned ready
sub update_reverse_dependencies_status {
    my $self = shift;
    my $task_id = shift;

    # $task_id is now COMPLETED
    $self->{task_status}->{$task_id} = $TASK_STATUS_COMPLETED;

    my @ready_tasks;

    # For each reverse dependencies we check if it exists new ready task
    my $reverse_dependencies = Jael::TasksGraph::get_reverse_dependencies($task_id);

  REV_IDS:
    for my $reverse_dependency (@{$reverse_dependencies}) {
        next unless defined $self->{tasks_owners}->{$reverse_dependency}; # We are not DHT_OWNER(reverse_dependency)

        my $dependencies = Jael::TasksGraph::get_dependencies($reverse_dependency);

        for my $dependency (@{$dependencies}) {
            # If one dependency is not completed, we check other tasks (go to first loop)
            if (not defined $self->{task_status}->{$dependency} or $self->{task_status}->{$dependency} != $TASK_STATUS_COMPLETED) {
                next REV_IDS;
            }
        }

        # All dependencies are completed => New ready task
        $self->{task_status}->{$reverse_dependency} = $TASK_STATUS_READY;
        push @ready_tasks, $reverse_dependency;
    }

    Jael::Debug::msg("task $task_id is now completed, new ready tasks: " . join(", ", @ready_tasks));

    return \@ready_tasks;
}

# Return machine owning task id
sub get_machine_owning {
    my $self = shift;
    my $task_id = shift;

    die "we are not DHT_OWNER of $task_id" if not defined $self->{tasks_owners}->{$task_id};
    return $self->{tasks_owners}->{$task_id};
}

1;
