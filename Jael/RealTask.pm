# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::RealTask;

use strict;
use warnings;
use overload '""' => \&stringify;

use Jael::Task;

# RealTask extends Task
use parent 'Jael::Task';

# Create a new real task defined by target name, commands, dependencies and reverse dependencies
# careful, tasks with dependencies are marked as non ready by defaul
# you need to update status when creating stolen tasks
sub new {
    my $class = shift;
    my $self = $class->SUPER::new(shift); # Call Task->new with target name

    $self->{commands} = shift;
    my $dependencies = shift;

    $self->{dependencies}->{$_} = 1 for @$dependencies;
    $self->{remaining_unfilled_dependencies} = scalar @$dependencies; #count how many deps we are still waiting for
    $self->{reverse_dependencies} = shift;
    $self->{reverse_dependencies} = [] if not defined $self->{reverse_dependencies}; # Main task

    # Set the initial task status : Ready or not ready
    if (keys %{$self->{dependencies}}) {
        $self->{status} = $Jael::Task::TASK_STATUS_NOT_READY;
    } else {
        $self->{status} = $Jael::Task::TASK_STATUS_READY;
    }

    bless $self, $class;
    Jael::Debug::msg('task', "created task {$self}");
    return $self;
}

sub stringify {
    my $self = shift;
	my $command = $self->{commands};
	$command = '' unless defined $command;
    return "TASK: " . $self->{target_name} . ": " . join(" ", keys %{$self->{dependencies}}) . "\n command : $command\n";
}

# Set the main task flag
sub mark_as_main_task {
    my $self = shift;
    $self->{is_main_task} = 1;
    return;
}

# Return always 0
sub is_virtual {
    return 0;
}

# Execute the task's commands and return 1 if it's the main task else 0
sub execute {
    my $self = shift;
	die "undefined command" unless defined $self->{commands};
	Jael::Debug::msg('task', "executing $self->{target_name} : command is $self->{commands}");
    system("$self->{commands}");
    return (defined $self->{is_main_task});
}

# Return real task id
sub get_id {
    my $self = shift;
    return "$self->{target_name}";
}

# Update the task's status
sub update_status {
    my $self = shift;
    my $new_status = shift;

    # One completed or failed task can not be updated
    # Downgrade status is not allowed (TASK_STATUS_READY to READY_WAITING_FOR_FILES for example)
    return if ($self->{status} == $Jael::Task::TASK_STATUS_COMPLETED or $self->{status} == $Jael::Task::TASK_STATUS_FAILED or
               ($self->{status} == $Jael::Task::TASK_STATUS_READY and $new_status == $Jael::Task::TASK_STATUS_READY_WAITING_FOR_FILES));

    # Update
    $self->{status} = $new_status;

    return;
}

# Set one dependency's task to 0 (if exists)
# Change the task status to STATUS_READY if it is necessary (no more dependencies)
sub unset_dependency {
    my $self = shift;
    my $dependency_id = shift;

    # No checked dependency here
    return if not defined $self->{dependencies}->{$dependency_id};

    # No update, the dependency is already unset
    return if $self->{dependencies}->{$dependency_id} == 0;

    # Unset dependency
    $self->{dependencies}->{$dependency_id} = 0;
    $self->{remaining_unfilled_dependencies}--;

    my @still_needed;

    for my $id (keys %{$self->{dependencies}}) {
        push @still_needed, $id if $self->{dependencies}->{$id};
    }

    Jael::Debug::msg('stack', "task $self->{target_name} still needs @still_needed");

    # Update status
    if ($self->{remaining_unfilled_dependencies} == 0) {
        $self->{status} = $Jael::Task::TASK_STATUS_READY_WAITING_FOR_FILES;
    }

    return;
}

1;
