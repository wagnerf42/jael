# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Task;

use strict;
use warnings;
use Readonly;
use base 'Exporter';
use Jael::Debug;

# Warning : Task class is abstract, please to use the following classes : VirtualTask & RealTask

our @EXPORT = qw($TASK_STATUS_READY $TASK_STATUS_READY_WAITING_FOR_FILES $TASK_STATUS_NOT_READY $TASK_STATUS_FAILED $TASK_STATUS_COMPLETED);

# Once in the system, tasks can be in one of the following states :
Readonly::Scalar our $TASK_STATUS_READY => 1;                   # All dependencies are ok, all files are here => ready to run
Readonly::Scalar our $TASK_STATUS_READY_WAITING_FOR_FILES => 2; # All dependencies are ok, but waiting for files
Readonly::Scalar our $TASK_STATUS_NOT_READY => 3;               # Some dependencies are not computed ye
Readonly::Scalar our $TASK_STATUS_FAILED => 4;                  # Task executed and failed
Readonly::Scalar our $TASK_STATUS_COMPLETED => 5;               # Task executed successfully

# Create a new Task (Real or Virtual) with one target name
sub new {
    my $class = shift;
    my $self = {};

    $self->{target_name} = shift;
    die "target name is undef" if not defined $self->{target_name};

    bless $self, $class;
    return $self;
}

# Check the task's status and return 1 if the task is READY
# Note: One Virtual task is always READY
sub is_ready {
    my $self = shift;
    return ($self->{status} == $TASK_STATUS_READY);
}

# Return the current task's status
sub get_status {
    my $self = shift;
    return $self->{status};
}

# Return the target name of the current task
sub get_target_name {
    my $self = shift;
    return $self->{target_name};
}

# Get dependencies id
# Note: use get_task of TaskGraph for the dependencies tasks
sub get_dependencies {
    my $self = shift;
    return $self->{dependencies};
}

# Get reverse dependencies id
# Note: use get_task of TaskGraph for the reverse dependencies tasks
sub get_reverse_dependencies {
    my $self = shift;
    return $self->{reverse_dependencies};
}

1;
