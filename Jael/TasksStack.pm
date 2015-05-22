# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::TasksStack;

use strict;
use warnings;
use overload '""' => \&stringify;
use threads;
use threads::shared;

# Create a new tasks stack
sub new {
    my $class = shift;
    my $self = {};

    $self->{tasks} = [];

    # Ensure array is shared
    share($self->{tasks});

    bless $self, $class;
    return $self;
}

sub stringify {
    my $self = shift;

    lock($self->{tasks});
    print STDERR "Tid " . threads->tid() . ": [" . join(", ", @{$self->{tasks}}) . "]\n";

    return;
}

# Add many tasks on stack
sub push_task {
    my $self = shift;

    lock($self->{tasks});
    push @{$self->{tasks}}, map {shared_clone($_)} @_;

    return;
}

# Pop the last task in the stack only if the task's status is READY else return undef
sub pop_task {
    my $self = shift;

    lock($self->{tasks});

    my $selected_task;
    my @remaining_tasks;

    while ((not defined $selected_task) and (@{$self->{tasks}})) {
        my $candidate_task = pop @{$self->{tasks}};

        if ($candidate_task->is_ready()) {
            $selected_task = $candidate_task;
            last;
        } else {
            push @remaining_tasks, $candidate_task;
        }
    }

    push @{$self->{tasks}}, @remaining_tasks;

    return $selected_task;
}

# Try to steal one task (real or virtual)
# Return undef if the steal isn't possible
sub steal_task {
    my $self = shift;
    my $task;
    my $selected_task;
    my @remaining_tasks;

    lock($self->{tasks});

    # Useless to steal if it's not enough tasks in stack
    return undef if @{$self->{tasks}} <= 1;

    while ((not defined $selected_task) and (@{$self->{tasks}})) {
        my $candidate_task = shift @{$self->{tasks}};
        my $status = $candidate_task->get_status();

        if ($status == $Jael::Task::TASK_STATUS_READY or $status == $Jael::Task::TASK_STATUS_READY_WAITING_FOR_FILES) {
            $selected_task = $candidate_task;
            last;
        } else {
            unshift @remaining_tasks, $candidate_task;
        }
    }

    unshift @{$self->{tasks}}, @remaining_tasks;

    return $selected_task;
}

# Get the tasks number in the stack
sub get_size {
    my $self = shift;

    lock($self->{tasks});

    # Force scalar, we doesn't return an array copy
    return scalar @{$self->{tasks}};
}

# Unset task id in all tasks dependencies
sub update_dependencies {
    my $self = shift;
    my $id = shift;

    lock($self->{tasks});
    $_->unset_dependency($id) for @{$self->{tasks}};

    return;
}

# Change task's status if task exists
sub change_task_status {
    my $self = shift;
    my $id = shift;
    my $new_status = shift;

    lock($self->{tasks});

    my @tasks = grep { $id eq $_->get_id() } @{$self->{tasks}};

    if (defined $tasks[0]) {
        $tasks[0]->update_status($new_status);
    }

    return;
}

# Try to change the status for each task (if all dependencies are checked)
sub set_ready_status_if_necessary {
    my $self = shift;
    my $task_id = shift;

    lock($self->{tasks});

  R_TASK:
    for my $task (@{$self->{tasks}}) {
        # If the task waiting (it's inevitably one real task)
        if ($task->get_status() == $Jael::Task::TASK_STATUS_READY_WAITING_FOR_FILES) {
            my $dependencies = $task->get_dependencies();
            Jael::Debug::msg("[TasksStack]checking $task with dependency " . $task->get_id());

            # If the new file is in the task's dependencies
            if (defined $dependencies->{$task_id}) {
                for my $dependency (keys %{$dependencies}) {
                    # One or more files are missing
                    if (not -e $dependency) {
                        Jael::Debug::msg("[TasksStack]dependency $dependency is not present (for " . $task->get_id() . ")");
                        next R_TASK; # Unable to update status
                    }
                }
            } else {
                Jael::Debug::msg("[TasksStack]undefined $task_id in dependencies of " . $task->get_id());
            }

            # The real task is now ready
            $task->update_status($Jael::Task::TASK_STATUS_READY);
        } else {
            Jael::Debug::msg("[TasksStack]in stack, status of " . $task->get_id() . " is " . $task->get_status());
        }
    }

    return;
}

1;
