package Jael::Stack;

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

sub shift {
    my $self = shift;
    
    lock($self->{elems});  
    my $elem = shift @{$self->{elems}};

    return $elem;
}

sub pop {
    my $self = shift;
    
    lock($self->{elems});  
    my $elem = pop @{$self->{elems}};

    return $elem;
}

sub push {
    my $self = shift;
    my $elem = shift;

    lock($self->{elems});
    push @{$self->{elems}}, $elem;

    return;
}

sub unshift {
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
