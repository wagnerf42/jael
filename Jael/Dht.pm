# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Dht;

use strict;
use warnings;
use Readonly;

# Status information stored for each task
# This information is NOT THE SAME is as the more detailed status of a Jael::Task object
Readonly::Scalar my $STATUS_READY     => 1; # All dependencies for this task are completed
Readonly::Scalar my $STATUS_NOT_READY => 2; # Some dependencies for this task are not completed
Readonly::Scalar my $STATUS_FAILED    => 3; # Task executed and failed
Readonly::Scalar my $STATUS_COMPLETED => 4; # Task executed and succeeded

sub new {
    my $class = shift;
    my $self = {};

    $self->{machine_owner_of_task_id} = {}; # Update by TASK_IS_PUSHED message
    
    bless $self, $class;
    
    return $self;
}

# Get not unique identifier for one task id in [0..n_machines]
# TODO : Temp hash function... Test others functions
sub hash_task_id {
    my $task_id = shift;
    my $machines_number = shift;
    my $hash_value = 0;
    
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

    $self->{machine_owner_of_task_id}{$task_id} = $machine_id;
    
    return;
}

#some task t1 status changed
#change its status
#prerequisite : we own t1
sub change_task_status {
    my $self = shift;
    my $task_id = shift;     # t1 task
    my $task_status = shift; # New status for t1
    #TODO
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
