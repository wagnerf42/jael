# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::ServerEngine;

use strict;
use warnings;
use Readonly;
use base 'Exporter';
use threads;
use threads::shared;
use IO::Socket;
use IO::Select;

# Auto-flush on socke
$| = 1;

use Jael::Protocol;
use Jael::Message;
use Jael::MessageBuffers;
use Jael::Debug;
use Jael::Paje;

our @EXPORT = qw($SENDING_PRIORITY_LOW $SENDING_PRIORITY_HIGH);

Readonly::Scalar my $PORT => 23456;

# Threads priority
Readonly::Scalar our $SENDING_PRIORITY_LOW => 0;
Readonly::Scalar our $SENDING_PRIORITY_HIGH => 1;

my $max_buffer_reading_size = 1024;

# Make a new server
# Parameters: ExecutionEngine, [machine 1, machine 2, ...]
#
# Example:
# 1, [m1, m2, m3, m2]
#      0   1   2   3
sub new {
    my $class = shift;
    my $self = {};

    bless $self, $class;

    # Shared data
    my @sh_messages_low :shared;
    my @sh_messages_high :shared;

    my $execution_engine = shift;

    $self->{id} = $execution_engine->get_id();

    my @machines_names :shared = @{$execution_engine->get_machines()};

    $self->{machines_names} = \@machines_names;
    $self->{machines_number} = @{$self->{machines_names}};

    # Messages list, one per thread
    $self->{sending_messages} = [];
    $self->{sending_messages}->[$SENDING_PRIORITY_LOW] = \@sh_messages_low;
    $self->{sending_messages}->[$SENDING_PRIORITY_HIGH] = \@sh_messages_high;

    $self->{message_buffers} = Jael::MessageBuffers->new();
    $self->{protocol} = Jael::Protocol->new($execution_engine, $self);
    $self->{sending_threads} = [];

    # Make threads
    my $thr_low = threads->create(\&th_send_with_priority, $self->{id}, $self->{machines_names}->[$self->{id}],
                                                      \@sh_messages_low, \@machines_names, $SENDING_PRIORITY_LOW);
    my $thr_high = threads->create(\&th_send_with_priority, $self->{id}, $self->{machines_names}->[$self->{id}],
                                                      \@sh_messages_high, \@machines_names, $SENDING_PRIORITY_HIGH);

    push @{$self->{sending_threads}}, $thr_low;
    push @{$self->{sending_threads}}, $thr_high;

    Jael::Paje::create_thread($thr_low->tid());
    Jael::Paje::create_thread($thr_high->tid());

    return $self;
}

sub run {
    my $self = shift;
    Jael::Debug::msg("[Server]starting new server (port=" . ($PORT + $self->{id}) . ", id=$self->{id})");

    # server port is PORT + id of current server
    $self->{server_socket} = IO::Socket::INET->new(LocalHost => $self->{machines_names}->[$self->{id}],
                                                   LocalPort => $PORT + $self->{id},
                                                   Listen => 1,
                                                   Reuse => 1,
                                                   Proto => 'tcp');

    die "Could not create socket: $!\n" unless $self->{server_socket};

    # we use select to find non blocking reads
    $self->{read_set} = IO::Select->new($self->{server_socket});

    while(my @ready = $self->{read_set}->can_read()) {
        for my $fh (@ready) {
	    # New connexion
            if ($fh == $self->{server_socket}) {
                Jael::Debug::msg("[Server]new connexion");
                my $new = $self->{server_socket}->accept;
                $self->{read_set}->add($new);
            }
	    # Receiving message...
            else {
                my $buffer;
                my $size = $max_buffer_reading_size;

                $fh->recv($buffer, $size);

                # Closing connexion
                if ($size == 0) {
                    Jael::Debug::msg("[Server]connection closed");
                    $self->{read_set}->remove($fh);
                    close($fh);
                }
                # Handle message
                else {
                    # We use the message protocol for each received message
                    my @received_messages = $self->{message_buffers}->incoming_data($fh, $buffer);
                    $self->{protocol}->incoming_message($_) for @received_messages;
                }
            }
        }
    }

    return;
}

# Broadcast to everyone but self
# slow and dumb broadcast with a loop
sub broadcast {
    my $self = shift;
    my $message = shift;

    Jael::Debug::msg("[Server]broadcasting $message");

    for my $machine_id (0..$#{$self->{machines_names}}) {
        next if $machine_id == $self->{id};
        Jael::Debug::msg("[Server]broadcast $machine_id");

        $self->send($machine_id, $message);
    }

    return;
}

# Broadcast to everyone except machines list
sub broadcast_except {
    my $self = shift;
    my $message = shift;
    my $except_list = shift;

    Jael::Debug::msg("[Server]broadcasting (except: " . join(",", @{$except_list}) . ") $message");

    for my $machine_id (0..$#{$self->{machines_names}}) {
        next if grep {$machine_id == $_} @{$except_list};
        Jael::Debug::msg("[Server]broadcast $machine_id");

        $self->send($machine_id, $message);
    }

    return;
}

# One sending thread
sub th_send_with_priority {
    my $id = shift;
    my $machine_name = shift;

    my $sending_sockets = {};     # Thread's sockets
    my $sending_messages = shift; # Messages list for the sockets
    my $machines_names = shift;   # Machines list
    my $priority = shift;         # Thread priority

    my $string;            # Message string
    my $target_machine_id; # Message id

    # Init the debug infos for the sending thread
    Jael::Debug::msg("[Server]creating sending thread");

    while (1) {
        {
            lock($sending_messages);
            cond_signal($sending_messages) unless @{$sending_messages}; # For wait_while_messages_exists
            cond_wait($sending_messages) until @{$sending_messages}; # Wait if nothing in messages array

            # Get message in the message list
            $target_machine_id = shift @{$sending_messages};
            $string = shift @{$sending_messages};
        }

        # Connect if socket doesn't exists
        connect_to($machines_names, $target_machine_id, $sending_sockets)
            unless exists $sending_sockets->{$target_machine_id};

        # Sending data
        my $socket = $sending_sockets->{$target_machine_id};
        Jael::Debug::msg("[Server]sending message (priority=$priority, target=$target_machine_id)");
        $socket->send($string) or die "unable to send to $target_machine_id: $!";
    }

    # Not reached
    return;
}

# Wait all messages are sent
sub wait_while_messages_exists {
    my $self = shift;

    my @priorities = ($SENDING_PRIORITY_LOW, $SENDING_PRIORITY_HIGH);

    for my $priority (@priorities) {
        lock($self->{sending_messages}->[$priority]);
        cond_wait($self->{sending_messages}->[$priority]) while @{$self->{sending_messages}->[$priority]};
    }

    return;
}

# Send function (For Server object)
sub send {
    my $self = shift;
    my $target_machine_id = shift;
    my $message = shift;

    # Source machine id = sender id
    $message->set_sender_id($self->{id});

    # Get or define priority
    # By default, it is a high priority message
    my $priority = $message->get_priority();
    $priority = $SENDING_PRIORITY_HIGH unless (defined $priority);

    # Add message in the the right messages lis
    {
        lock($self->{sending_messages}->[$priority]);
        push @{$self->{sending_messages}->[$priority]}, ($target_machine_id, $message->pack());
        Jael::Debug::msg("[Server]new message in queue (type=" . $message->get_type() .
                         ", id_dest=$target_machine_id, priority=$priority)");
        cond_signal($self->{sending_messages}->[$priority]);
    }

    return;
}

sub kill_sending_threads {
    my $self = shift;

    Jael::Debug::msg("[Server]kill sending threads");

    $_->kill('SIGUSR1') for @{$self->{sending_threads}};

    for my $priority (@{$self->{sending_messages}}) {
        {
            lock($priority);
            cond_signal($priority);
        }
    }

    return;
}

# Add socket in sockets list (For sending thread, not Server object)
sub connect_to {
    my $machines_names = shift;
    my $machine_id = shift;
    my $sending_sockets = shift;

    my $port = $PORT + $machine_id;
    my $machine = $machines_names->[$machine_id];

    while (not defined $sending_sockets->{$machine_id}) {
        Jael::Debug::msg("[Server]connect_to (machine_addr=$machine, port=$port)");

        $sending_sockets->{$machine_id} = IO::Socket::INET->new(
            PeerAddr => $machine,
            PeerPort => $port,
            Proto => 'tcp'
            );

        sleep(2);
    }

    Jael::Debug::msg("[Server]opened connection to $machine_id");

    return;
}

1;
