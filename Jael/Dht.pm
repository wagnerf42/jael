# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Dht;

use strict;
use warnings;
use Readonly;

# Machines number on network
my $machines_number;

# Status information stored for each task
# This information is NOT THE SAME is as the more detailed status of a Jael::Task object
Readonly::Scalar my $DHT_TASK_STATUS_READY     => 1; # All dependencies for this task are completed
Readonly::Scalar my $DHT_TASK_STATUS_NOT_READY => 2; # Some dependencies for this task are not completed
Readonly::Scalar my $DHT_TASK_STATUS_FAILED    => 3; # Task executed and failed
Readonly::Scalar my $DHT_TASK_STATUS_COMPLETED => 4; # Task executed and succeeded

# Make a new Dht, no parameters
sub new {
    my $class = shift;
    my $self = {};
    
    $self->{machine_owner_of_task} = {};       # Update by TASK_IS_PUSHED message
    $self->{task_status} = {};                 # Update by TASK_COMPUTATION_COMPLETED message
    $self->{task_forked} = {};                 # Update by FORK_REQUEST message
    $self->{machines_owner_of_task_data} = {}; # Update by TASK_COMPUTATION_COMPLETED message
        
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

# Set machine owning task
sub set_machine_owning {
    my $self = shift;
    my $task_id = shift;
    my $machine_id = shift;

    $self->{machine_owner_of_task}->{$task_id} = $machine_id;
    
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

sub compute_machines_owning_tasks_depending_on {
    my $self = shift;
    my $task_id = shift;

    # Get tasks depending on $task_id
    my $sons_task_id = Jael::TasksGraph::get_reverse_dependencies($task_id);

    my %owners;
    
    # Get owners
    for my $son_task_id (@{$sons_task_id}) {
        my $owner = hash_task_id($son_task_id); # Get DHT_OWNER($son_task_id)
        $owners{$owner} = 1;
    }

    return (keys %owners);
}

# Update the owners list of one task data
sub add_task_data_owner {
    my $self = shift;
    my $task_id = shift;
    my $machine_id = shift;
    
    push @{$self->{machines_owner_of_task_data}->{$task_id}}, $machine_id;

    return;
}

#some task t1 status changed
#if we own any task t2 depending on t1
#update dependencies on t2
#return the list of tasks which turned ready
sub change_dependencies_status {
}

#TODO: can the machine change and thus can we send information to bad target ?
#return machine owning this task
sub get_machine_owning {
}

#return list of machines having target
sub locate {
}

#add to list of machines having target
sub update_location {
}

#return machine id for dht owning this task
sub get_dht_id_for_task {
}

1;
