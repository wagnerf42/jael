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

    # C solution, it's not easy in perl with shared data
    
    # Pop the first ready task
    for (my $i = @{$self->{elems}} - 1; $i >= 0; $i--) {
        if(${$self->{elems}}[$i]->{status} == Jael::Task::STATUS_READY) {
            # Splice not implemented for shared arrays, so it's one solution :
            my $task = ${$self->{elems}}[$i];
            
            for (my $j = $i; $j < @{$self->{elems}} - 1; $j++) {
                ${$self->{elems}}[$j] = ${$self->{elems}}[$j + 1];
            }

            pop @{$self->{elems}};
            return $task;
        }
    }
    
    return;
}

sub push_task {
    my $self = shift;

    lock($self->{elems});    
    push @{$self->{elems}}, shared_clone(shift);

    return;
}

# Same as push_task, but take one array reference of tasks
sub push_several_tasks {
    my $self = shift;
    my $elems = shift;
    
    lock($self->{elems});

    foreach (@{$elems}) {
        push @{$self->{elems}}, shared_clone($_);
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

    foreach (@{$self->{elems}}) {
        $_->unset_dependency($id);
    }

    return;
}

sub stringify {
    my $self = shift;
    
    lock($self->{elems});  
    print STDERR "Tid " . threads->tid() . ": [" . join(", ", @{$self->{elems}}) . "]\n";

    return;
}

1;
