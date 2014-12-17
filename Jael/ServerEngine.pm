package Jael::ServerEngine;

use strict;
use warnings;
use IO::Socket;
use IO::Select;
use Jael::Protocol;
use Jael::MessageBuffers;
use Jael::Debug;

use constant PORT => 2345;

sub new {
	my $class = shift;
	my $self = {};
	$self->{id} = shift;
	$self->{sending_sockets} = {};
	$self->{machines_names} = [@_];
	$self->{machines_number} = @{$self->{machines_names}};
	$self->{message_buffers} = new Jael::MessageBuffers;
	bless $self, $class;
	$self->{protocol} = new Jael::Protocol($self);
	return $self;
}

sub run {
	my $self = shift;
	Jael::Debug::msg('starting new server');
	$self->{server_socket} = new IO::Socket::INET(LocalHost => $self->{machines_names}->[$self->{id}], LocalPort => PORT+$self->{id}, Proto => 'tcp', Listen => 1, Reuse => 1);
	die "Could not create socket: $!\n" unless $self->{server_socket};

	$self->{read_set} = new IO::Select(); # create handle set for reading
	$self->{read_set}->add($self->{server_socket}); # add the main socket to the set

	while (1) {
		my ($rh_set) = IO::Select->select($self->{read_set}, undef, undef, 0);
		for my $rh (@{$rh_set}) {
			if ($rh == $self->{server_socket}) {
				my $new_socket = $rh->accept();
				$self->{read_set}->add($new_socket);
			}
			else {
				my $buffer = <$rh>;
				if ($buffer) {
					$self->{message_buffers}->incoming_data($rh, $buffer);
				} else {
					$self->{read_set}->remove($rh);
					close($rh);
				}
			}
		}
	}
}

#broadcast to everyone but self
#slow and dumb broadcast with a loop
sub broadcast {
	my $self = shift;
	my $message = shift;
	Jael::Debug::msg("broadcasting $message");
	for my $machine_id (0..$#{$self->{machines_names}}) {
		next if $machine_id == $self->{id};
		$self->send($machine_id, $message);
	}
}

sub send {
	my $self = shift;
	my $target_machine_id = shift;
	my $message = shift;
	$message->set_sender_id($self->{id});
	$self->connect_to($target_machine_id) unless exists $self->{sending_sockets}->{$target_machine_id};
	my $socket = $self->{sending_sockets}->{$target_machine_id};
	my $string = $message->pack();
	print $socket $string;
}

sub connect_to {
	my $self = shift;
	my $machine_id = shift;

	my $port = PORT + $machine_id;
	my $machine = $self->{machines_names}->[$machine_id];
	while (not defined $self->{sending_sockets}->{$machine_id}) {
		$self->{sending_sockets}->{$machine_id} = IO::Socket::INET->new(
			PeerAddr => $machine,
			PeerPort => $port,
			Proto => 'tcp'
		);
		sleep(0.1);
	}
	Jael::Debug::msg("opened connection to $machine_id");
}

1;
