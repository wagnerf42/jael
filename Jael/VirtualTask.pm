# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::VirtualTask;

use strict;
use warnings;
use overload '""' => \&stringify;
use Readonly;
use base 'Exporter';

use Jael::Task;

# VirtualTask extends Task
use parent 'Jael::Task';

our @EXPORT = qw($VIRTUAL_TASK_PREFIX);

Readonly::Scalar our $VIRTUAL_TASK_PREFIX => 'virtual//';

# Create a new virtual task defined by one target name and reverse dependencies
sub new {
    my $class = shift;
    my $self = $class->SUPER::new(shift); # Call Task->new with target name

    # It exists normaly at least one task id (real task)
    $self->{reverse_dependencies} = shift;
    $self->{dependencies} = {}; # No dependencies for virtual task

    # Virtual task is always ready
    $self->{status} = $Jael::Task::TASK_STATUS_READY;

    bless $self, $class;
    return $self;
}

sub stringify {
    my $self = shift;
    return $VIRTUAL_TASK_PREFIX . "$self->{target_name}: " . join(" ", @{$self->{tasks_to_generate}});
}

# Return always 1
sub is_virtual {
    return 1;
}

# Return the virtual task id
sub get_id {
    my $self = shift;
    return $VIRTUAL_TASK_PREFIX . "$self->{target_name}";
}

# Return the tasks to generate:
# - The 'target name'
# - The reverse dependencies of the real task 'target name' with virtual prefix
sub get_tasks_to_generate {
    my $self = shift;
    return [ map {Jael::TasksGraph::get_task($_)} @{$self->{reverse_dependencies}} ];
}

1;
