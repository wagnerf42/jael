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

# Pop the last task in the stack only is the task's status is READY else return undef
sub pop_task {
    my $self = shift;
    
    lock($self->{tasks});  

    my $selected_task;
    my @remaining_tasks;
    
    while ((not defined $selected_task) and (@{$self->{tasks}})) {
        my $candidate_task = pop @{$self->{tasks}};
        
        if ($candidate_task->is_ready()) {
            $selected_task = $candidate_task;
        } else {
            push @remaining_tasks, $candidate_task;
        }
    }

    push @{$self->{tasks}}, @remaining_tasks;
    
    return $selected_task;
}

# Add one task in the stack
sub push_task {
    my $self = shift;

    lock($self->{tasks});
    
    for my $task (@_) {
        push @{$self->{tasks}}, shared_clone($task);
    }

    return;
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

1;
