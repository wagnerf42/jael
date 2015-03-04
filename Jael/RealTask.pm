# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::RealTask;

use strict;
use warnings;
use overload '""' => \&stringify;

# RealTask extends Task
use parent 'Jael::Task';

# Parameters : Target name, command, [deps] 
sub new {
    my $class = shift;
    my $self = $class->SUPER::new(shift); # Call Task->new with target name
    
    $self->{command} = shift;
    
    my $deps = shift;

    # Set dependencies
    $self->{dependencies} = {};

    if (defined $deps) {
        my @deps = split(/\s+/, $deps);
        for my $dep (grep {$_ ne ''} @deps) {
            $self->{dependencies}->{$dep} = 1;
        }
    }

    # Set the initial task status : Ready or not ready
    if (%{$self->{dependencies}}) {
        $self->{status} = Jael::Task::STATUS_NOT_READY;
    } else {
        $self->{status} = Jael::Task::STATUS_READY;
    }
    
    bless $self, $class;
    
    return $self;
}

sub stringify {
    my $self = shift;
    return $self->{target_name} . ": " . join(" ", keys %{$self->{dependencies}}) . "\n\t" . $self->{command} . "\n";
}

sub get_id {
    my $self = shift;
    return "$self->{target_name}";
}

sub get_command {
    my $self = shift;
    return $self->{command};
}

1;
