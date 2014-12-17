package Jael::Dht;

use strict;
use warnings;

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
	my $task_id = shift;
	my $task_status = shift;
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
