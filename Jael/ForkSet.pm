# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::ForkSet;

use strict;
use warnings;
use Readonly;
use threads;
use threads::shared;

our @EXPORT = qw($FORK_REQUEST_WAIT FORK_REQUEST_DONE);

# Fork status for current process
Readonly::Scalar my $FORK_REQUEST_WAIT => 0; # Wait response
Readonly::Scalar my $FORK_REQUEST_DONE => 1; # We have response (positive or negative)

# Make a new ForkSet, no parameters
sub new {
    my $class = shift;
    my $self = {};

    # Multiple threads can request one task => shared protection
    my %requested_tasks :shared;
    $self->{requested_tasks} = \%requested_tasks;

    my $requested_tasks_number :shared;
    $self->{requested_tasks_number} = \$requested_tasks_number;

    bless $self, $class;

    return $self;
}

# Test if one task is requested
sub is_requested {
    my $self = shift;
    my $task_id = shift;

    return (defined $self->{requested_tasks}->{$task_id});
}

# Set the FORK_REQUEST_WAIT status, returns -1 if task_id is already defined
sub set_wait_status {
    my $self = shift;
    my $task_id = shift;

    {
        lock($self->{requested_tasks});

        # The tasks was already requested
        return -1 if defined $self->{requested_tasks}->{$task_id};

        $self->{requested_tasks}->{$task_id} = $FORK_REQUEST_WAIT;
    }

    {
        lock($self->{requested_tasks_number});
        ${$self->{requested_tasks_number}}++;
    }

    return 0;
}

# Set the done status, returns -1 if FORK_REQUEST_DONE is already set
sub set_done_status {
    my $self = shift;
    my $task_id = shift;

    {
        lock($self->{requested_tasks});
        die "$task_id is not defined !" if not defined $self->{requested_tasks}->{$task_id};
        return -1 if $self->{requested_tasks}->{$task_id} == $FORK_REQUEST_DONE;
        $self->{requested_tasks}->{$task_id} = $FORK_REQUEST_DONE;
    }

    {
        lock($self->{requested_tasks_number});
        ${$self->{requested_tasks_number}}--;
    }

    return;
}

sub get_requests_number {
    my $self = shift;
    lock($self->{requested_tasks_number});
    return $self->{requested_tasks_number} > 0;
}

sub get_status {
    my $self = shift;
    my $task_id = shift;

    lock($self->{requested_tasks});
    return $self->{requested_tasks}->{$task_id};
}

1;
