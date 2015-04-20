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
            push @remaining_tasks, @{$self->{tasks}};
            undef @{$self->{tasks}};
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

    # TODO: there is a risk of stealing several times the same task for now
    # we could remove problem by refusing to be stolen if only few tasks are ready
    while ((not defined $selected_task) and (@{$self->{tasks}})) {
        my $candidate_task = shift @{$self->{tasks}};
        my $status = $candidate_task->get_status();

        if ($status == $Jael::Task::TASK_STATUS_READY or $status == $Jael::Task::TASK_STATUS_READY_WAITING_FOR_FILES) {
            $selected_task = $candidate_task;
            unshift @remaining_tasks, $candidate_task;
            undef @{$self->{tasks}};
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

1;
