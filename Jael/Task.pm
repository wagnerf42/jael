# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Task;

use strict;
use warnings;

# Warning : Task class is abstract, please to use the following classes : VirtualTask & RealTask

our (@ISA, @EXPORT);
BEGIN {
    require Exporter;
    @ISA = qw(Exporter);
    @EXPORT = qw(STATUS_READY STATUS_READY_WAITING_FOR_FILES STATUS_NOT_READY STATUS_FAILED STATUS_COMPLETED);
}

# Once in the system, tasks can be in one of the following states :
use constant {
    STATUS_READY => 1,                   # All dependencies are ok, all files are here => ready to run
    STATUS_READY_WAITING_FOR_FILES => 2, # All dependencies are ok, but waiting for files
    STATUS_NOT_READY => 3,               # Some dependencies are not computed yet
    STATUS_FAILED => 4,                  # Task executed and failed
    STATUS_COMPLETED => 5                # Task executed successfully
};

sub new {
    my $class = shift;
    my $self = {};
    
    $self->{target_name} = shift;
    
    bless $self, $class;

    return $self;
}

sub is_ready {
    my $self = shift;
    return ($self->{status} == STATUS_READY);
}

sub get_target_name {
    my $self = shift;
    return $self->{target_name};
}

sub get_dependencies {
    my $self = shift;    
    return (keys %{$self->{dependencies}});
}

# Set one dependency's task to 0 (if exists)
# Change the task status to STATUS_READY if it is necessary (no more dependencies)
sub unset_dependency {
    my $self = shift;
    my $id = shift;

    if (defined ${$self->{dependencies}}{$id}) {
        # No update, the dependency is already unset
        return if (${$self->{dependencies}}{$id} == 0);

        # Unset dependency
        ${$self->{dependencies}}{$id} = 0;

        # Update status
        foreach (values %{$self->{dependencies}}) {
            return if $_ != 0; # It exists one active dependency
        }

        $self->{status} = STATUS_READY;
    }

    return;
}

1;
