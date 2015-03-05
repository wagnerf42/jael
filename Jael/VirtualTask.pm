# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::VirtualTask;

use strict;
use warnings;
use overload '""' => \&stringify;

# VirtualTask extends Task
use parent 'Jael::Task';

our (@ISA, @EXPORT);
BEGIN {
    require Exporter;
    push @ISA, qw(Exporter);
    push @EXPORT, qw(VIRTUAL_TASK_PREFIX);
}

use constant VIRTUAL_TASK_PREFIX => 'virtual//';
    
# Parameters : Target name, \@deps, \@tasks_to_generate
sub new {
    my $class = shift;
    my $self = $class->SUPER::new(shift); # Call Task->new with target name

    my $deps = shift;

    if (defined $deps) {
        $self->{dependencies} = $deps;
    } else {
        $self->{dependencies} = {};
    }
    
    $self->{tasks_to_generate} = shift;

    # Virtual task is always ready
    $self->{status} = Jael::Task::STATUS_READY;
    
    bless $self, $class;

    return $self;
}

sub is_virtual {
    return 1;
}

sub stringify {
    my $self = shift;
    return VIRTUAL_TASK_PREFIX . "$self->{target_name}: " . join(" ", @{$self->{tasks_to_generate}});
}

sub get_id {
    my $self = shift;
    return VIRTUAL_TASK_PREFIX . "$self->{target_name}";
}

sub get_tasks_to_generate {
    my $self = shift;
    return $self->{tasks_to_generate};
}

1;
