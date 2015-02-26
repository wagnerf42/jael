# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Stack;

use strict;
use warnings;

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

sub shift_value {
    my $self = shift;
    
    lock($self->{elems});  
    my $elem = shift @{$self->{elems}};

    return $elem;
}

sub pop_value {
    my $self = shift;
    
    lock($self->{elems});  
    my $elem = pop @{$self->{elems}};

    return $elem;
}

sub push_value {
    my $self = shift;
    my $elem = shift;

    lock($self->{elems});
    push @{$self->{elems}}, $elem;

    return;
}

sub unshift_value {
    my $self = shift;
    my $elem = shift;
    
    lock($self->{elems});  
    unshift @{$self->{elems}}, $elem;

    return;
}

sub get_size {
    my $self = shift;
    
    lock($self->{elems});
    # Force scalar, we doesn't return the array reference
    return scalar @{$self->{elems}};
}

sub print {
    my $self = shift;
    
    lock($self->{elems});  
    print STDERR "Tid " . threads->tid() . ": [" . join(", ", @{$self->{elems}}) . "]\n";

    return;
}

1;
