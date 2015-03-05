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
    
    bless $self, $class;
    
    return $self;
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

#set machine owning task
sub set_machine_owning {
}

1;
