# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Dht;

use strict;
use warnings;

use Jael::Task;
use Jael::VirtualTask qw($VIRTUAL_TASK_PREFIX);
use Carp;

# We need to know number of machines in hash function
my $machines_number;

# Make a new Dht, no parameters
sub new {
    my $class = shift;
    my $self = {};
	$self->{id} = shift; # who we are

	# remember for each task who is holding it
    $self->{tasks_owners} = {}; # Update by TASK_IS_PUSHED
	# remember for each task if forked yet or not
    $self->{task_forked} = {};  # Update by FORK_REQUEST
	# remember for each task a list of machines owning the corresponding data
    $self->{data_owners} = {};  # Update by TASK_COMPUTATION_COMPLETED
	# remember for each task the hash of dependencies which already finished
	$self->{completed_tasks_dependencies} = {};

    bless $self, $class;

    return $self;
}

# return true if given task has all its dependencies which already finished
sub all_dependencies_finished {
	my $self = shift;
	my $task_id = shift;
	confess "i am not owner of $task_id" unless $self->owns($task_id);
	confess "virtual task accessed in dht : $task_id" if $task_id =~/^$Jael::VirtualTask::VIRTUAL_TASK_PREFIX/;
	my $dependencies = Jael::TasksGraph::get_dependencies($task_id);
	for my $dependency (@$dependencies) {
		return 0 unless (defined $self->{completed_tasks_dependencies}->{$task_id}->{$dependency});
	}
	return 1;
}

sub mark_dependency_finished {
	my $self = shift;
	my $task_id = shift;
	my $dependency = shift;
	confess "i am not owner of $task_id" unless $self->owns($task_id);
	confess "virtual task accessed in dht : $task_id" if $task_id =~/^$Jael::VirtualTask::VIRTUAL_TASK_PREFIX/;
	Jael::Debug::msg('dht', "we store in dht that dep $dependency is now completed for task $task_id");
	$self->{completed_tasks_dependencies}->{$task_id}->{$dependency} = 1;
	return;
}

# Define the machines number on network
sub set_machines_number {
    confess "machines number is already defined !" if defined $machines_number;
    $machines_number = shift;

    return;
}


# are we responsible for given task ?
sub owns {
	my $self = shift;
	my $task_id = shift;
	return (hash_task_id($task_id) == $self->{id});
}

# Get not unique identifier for one task id in [0..n_machines]
sub hash_task_id {
    my $task_id = shift;
    my $hash_value = 0;

    $task_id = $1 if ($task_id =~ /^$VIRTUAL_TASK_PREFIX(.*)/);

    for my $c (split //, $task_id) {
        $hash_value = ($hash_value << 5) | ($hash_value >> 27);
        $hash_value += ord($c);
    }

    $hash_value %= $machines_number;

    Jael::Debug::msg('hash_value', "Hash value for '$task_id' : $hash_value");

    return $hash_value;
}

# Set machine owning task, not the DHT_OWNER but the machine's stack using this task.
# careful : puts status to not ready
sub set_machine_owning {
    my $self = shift;
    my $task_id = shift;
	confess "we are not responsible for $task_id" unless $self->owns($task_id);
	confess "virtual task accessed in dht : $task_id" if $task_id =~/^$Jael::VirtualTask::VIRTUAL_TASK_PREFIX/;
    my $machine_id = shift;
	Jael::Debug::msg('dht', "we record in dht that task $task_id is now physically on machine $machine_id");

    $self->{tasks_owners}->{$task_id} = $machine_id;

    return;
}

# Fork request by one machine id for one task id
# Check and set fork status
sub fork_request {
    my $self = shift;
    my $task_id = shift;
	confess "we are not responsible for $task_id" unless $self->owns($task_id);
	confess "virtual task accessed in dht : $task_id" if $task_id =~/^$Jael::VirtualTask::VIRTUAL_TASK_PREFIX/;
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
	confess "we are not responsible for $task_id" unless $self->owns($task_id);
	confess "virtual task accessed in dht : $task_id" if $task_id =~/^$Jael::VirtualTask::VIRTUAL_TASK_PREFIX/;

    # Get tasks depending on $task_id
    my $sons_task_id = Jael::TasksGraph::get_reverse_dependencies($task_id);

    my %owners;

    # Get owners
    for my $son_task_id (@{$sons_task_id}) {
        my $owner = hash_task_id($son_task_id);
		Jael::Debug::msg('dht', "$task_id completed we need to inform $owner that status of $son_task_id might change");
        $owners{$owner} = 1;
    }

    return (keys %owners);
}

# Update the owners list of one task data
sub add_data_owner {
    my $self = shift;
    my $task_id = shift;
	confess "we are not responsible for $task_id" unless $self->owns($task_id);
	confess "virtual task accessed in dht : $task_id" if $task_id =~/^$Jael::VirtualTask::VIRTUAL_TASK_PREFIX/;
    my $machine_id = shift;

	Jael::Debug::msg('dht', "we set $machine_id as data owner for $task_id");
    push @{$self->{data_owners}->{$task_id}}, $machine_id;

    return;
}

# Return list of machines having data
sub get_data_owners {
    my $self = shift;
    my $task_id = shift;

	confess "we are not responsible for $task_id" unless $self->owns($task_id);
	confess "virtual task accessed in dht : $task_id" if $task_id =~/^$Jael::VirtualTask::VIRTUAL_TASK_PREFIX/;

    return [] if not defined $self->{data_owners}->{$task_id};
    return $self->{data_owners}->{$task_id};
}

# One task is now completed => Check if we can update the reverse dependencies to READY state
# Return the list of existing tasks which turned ready or file tasks which turned ready
sub update_reverse_dependencies_status {
    my $self = shift;
    my $task_id = shift;
	confess "virtual task accessed in dht : $task_id" if $task_id =~/^$Jael::VirtualTask::VIRTUAL_TASK_PREFIX/;

    # update deps information for each task depending on the one which just completed
    my $reverse_dependencies = Jael::TasksGraph::get_reverse_dependencies($task_id);

    my @ready_tasks;
	# update info and get list of ready tasks
	for my $task (@$reverse_dependencies) {
		next unless $self->owns($task);
		$self->mark_dependency_finished($task, $task_id);
		if ($self->all_dependencies_finished($task)) {
			push @ready_tasks, $task;
		}
	}

    Jael::Debug::msg('dht', "[Dht]task $task_id is now completed, candidate ready tasks: " . join(", ", @ready_tasks));
	#now filter list of ready tasks to retrieve only the ones already created or file tasks
	my @existing_ready_tasks = grep {defined $self->{tasks_owners}->{$_} or Jael::TasksGraph::is_file_transfer_task($_)} @ready_tasks;

    Jael::Debug::msg('dht', "[Dht]task $task_id is now completed, new ready tasks: " . join(", ", @existing_ready_tasks));
    return \@existing_ready_tasks;
}

# Return one list of completed dependencies
# for the real task corresponding to the given virtual task
sub get_completed_dependencies {
    my $self = shift;
    my $virtual_task_id = shift;

    confess "not virtual : '$virtual_task_id'" unless $virtual_task_id =~ /$Jael::VirtualTask::VIRTUAL_TASK_PREFIX(\S+)/;

    my $real_task_id = $1;
	confess "we are not responsible for $real_task_id" unless $self->owns($real_task_id);
	return [keys %{$self->{completed_tasks_dependencies}->{$real_task_id}}];
}

# Return machine owning task id
sub get_machine_owning {
    my $self = shift;
    my $task_id = shift;

	confess "we are not responsible for $task_id" unless $self->owns($task_id);
	confess "virtual task accessed in dht : $task_id" if $task_id =~/^$Jael::VirtualTask::VIRTUAL_TASK_PREFIX/;
    confess "[Dht] $task_id was never created" unless defined $self->{tasks_owners}->{$task_id};

    return $self->{tasks_owners}->{$task_id};
}

1;
