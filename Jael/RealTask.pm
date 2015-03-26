# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::RealTask;

use strict;
use warnings;
use overload '""' => \&stringify;

use Jael::Task;

# RealTask extends Task
use parent 'Jael::Task';

# Create a new real task defined by target name, commands, dependencies and reverse dependencies
sub new {
    my $class = shift;
    my $self = $class->SUPER::new(shift); # Call Task->new with target name
    
    $self->{commands} = shift;
    my $dependencies = shift;
    
    %{$self->{dependencies}} = map { $_ => 1 } @{$dependencies};
    $self->{reverse_dependencies} = shift;
    $self->{reverse_dependencies} = [] if not defined $self->{reverse_dependencies}; # Main task
    
    # Set the initial task status : Ready or not ready
    if (keys %{$self->{dependencies}}) {
        $self->{status} = $Jael::Task::TASK_STATUS_NOT_READY;
    } else {
        $self->{status} = $Jael::Task::TASK_STATUS_READY;
    }
    
    bless $self, $class;
    return $self;
}

sub stringify {
    my $self = shift;
    return "TASK: " . $self->{target_name} . ": " . join(" ", keys %{$self->{dependencies}}) . "\n" . $self->{commands} . "\n";
}

# Set the main task flag
sub mark_as_main_task {
    my $self = shift;
    $self->{is_main_task} = 1;
    return;
}

# Return always 0
sub is_virtual {
    return 0;
}

# Execute the task's commands and return 1 if it's the main task else 0
sub execute {
    my $self = shift;
    system("$self->{commands}");
    return (defined $self->{is_main_task});
}

# Return real task id
sub get_id {
    my $self = shift;
    return "$self->{target_name}";
}

# Set one dependency's task to 0 (if exists)
# Change the task status to STATUS_READY if it is necessary (no more dependencies)
sub unset_dependency {
    my $self = shift;
    my $dependency_id = shift;

    # No checked dependency here
    return if not defined $self->{dependencies}->{$dependency_id};
    
    # No update, the dependency is already unset
    return if $self->{dependencies}->{$dependency_id} == 0;

    # Unset dependency
    $self->{dependencies}->{$dependency_id} = 0;

    # Update status
    for (values %{$self->{dependencies}}) {
        return if $_ != 0; # It exists one active dependency
    }

    # No active dependencies
    $self->{status} = $Jael::Task::TASK_STATUS_READY;
    
    return;
}

1;
