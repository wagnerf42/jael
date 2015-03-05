# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::TasksStack;

use strict;
use warnings;
use overload '""' => \&stringify;

use threads;
use threads::shared;

sub new {
    my $class = shift;
    my $self = {};
    
    $self->{elems} = [];

    # Ensure array is shared
    share($self->{elems});
    
    bless $self, $class;
    
    return $self;
}

sub pop_task {
    my $self = shift;
    
    lock($self->{elems});  

    my $selected_task;
    my @remaining_tasks;
    
    while ((not defined $selected_task) and (@{$self->{elems}})) {
        my $candidate_task = pop @{$self->{elems}};
        
        if ($candidate_task->is_ready()) {
            $selected_task = $candidate_task;
        } else {
            push @remaining_tasks, $candidate_task;
        }
    }

    push @{$self->{elems}}, @remaining_tasks;
    
    return $selected_task;
}

sub push_task {
    my $self = shift;

    lock($self->{elems});
    for my $task (@_) {
        push @{$self->{elems}}, shared_clone($task);
    }

    return;
}

sub get_size {
    my $self = shift;
    
    lock($self->{elems});
    
    # Force scalar, we doesn't return an array copy
    return scalar @{$self->{elems}};
}

# Unset task id in all tasks dependencies
sub update_dependencies {
    my $self = shift;
    my $id = shift;

    lock($self->{elems});

    $_->unset_dependency($id) for @{$self->{elems}};

    return;
}

sub stringify {
    my $self = shift;
    
    lock($self->{elems});  
    print STDERR "Tid " . threads->tid() . ": [" . join(", ", @{$self->{elems}}) . "]\n";

    return;
}

1;
