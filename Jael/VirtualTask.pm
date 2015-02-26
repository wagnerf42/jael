# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::VirtualTask;

use strict;
use warnings;
use overload '""' => \&stringify;

# VirtualTask extends Task
use parent 'Jael::Task';

# Parameters : Target name, \@deps, \@tasks_to_generate
sub new {
    my $class = shift;
    my $self = $class->SUPER::new(shift); # Call Task->new with target name

    my $deps = shift;

    if (defined $deps) {
        $self->{dependencies} = $deps;
    } else {
        $self->{dependencies} = [];
    }
    
    $self->{tasks_to_generate} = shift;
    
    bless $self, $class;

    return $self;
}

sub stringify {
    my $self = shift;
    return "virtual:$self->{target_name}: " . join(" ", @{$self->{tasks_to_generate}}) . "\n";
}

sub get_id {
    my $self = shift;
    return "virtual:$self->{target_name}";
}

1;
