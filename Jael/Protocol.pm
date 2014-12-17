package Jael::Protocol;

#this package handles protocol logic
#how to react on incoming messages

use strict;
use warnings;
use Jael::Message;
use Jael::Task;

sub new {
	my $class = shift;
	my $self = {};
	$self->{server} = shift;
	bless $self, $class;
	return $self;
}

sub incoming_message {
	my $self = shift;
	my $message = shift;
	my $type = $message->get_type();
	if ($type == TASK_COMPUTATION_COMPLETED) {
		my $task_id = $message->get_task_id();
		$self->{dht}->change_task_status($task_id, STATUS_COMPLETED);
		my @machines_to_inform = $self->{dht}->compute_machines_owning_tasks_depending_on($task_id);
		for my $machine_id (@machines_to_inform) {
			$self->{server}->send($machine_id, new Jael::Message(DEPENDENCIES_UPDATE_TASK_COMPLETED, $task_id));
		}
	} elsif ($type == DEPENDENCIES_UPDATE_TASK_COMPLETED) {
		my $task_id = $message->get_task_id();
		my @ready_tasks_ids = $self->{dht}->change_dependencies_status($task_id, STATUS_COMPLETED);
		for my $ready_task_id (@ready_tasks_ids) {
			my $machine_id = $self->{dht}->get_machine_owning($ready_task_id);
			$self->{server}->send($machine_id, new Jael::Message(DEPENDENCIES_UPDATE_TASK_READY, $ready_task_id));
		}
	} elsif ($type == DEPENDENCIES_UPDATE_TASK_READY) {
		$self->{stack}->change_task_status($message->get_task_id(), STATUS_READY);
	} elsif ($type == DATA_LOCALISATION) {
		my $task_id = $message->get_task_id();
		my @machines = $self->{dht}->locate($task_id);
		$self->{server}->send($message->get_sender_id(), new Jael::Message(DATA_LOCATED, $task_id, @machines));
	} elsif ($type == DATA_LOCATED) {
		die 'TODO';
	} elsif ($type == DATA_DUPLICATED) {
		my $task_id = $message->get_task_id();
		my $sender_id = $message->get_sender_id();
		$self->{dht}->update_location($task_id, $sender_id);
	} elsif ($type == END_ALL) {
		die 'TODO';
	} elsif ($type == STEAL_REQUEST) {
		my $task_id = $self->{task}->steal_task();
		my $sender_id = $message->get_sender_id();
		if (defined $task_id) {
			$self->{server}->send($sender_id, new Jael::Message(STEAL_SUCCESS, $task_id));
		} else {
			$self->{server}->send($sender_id, new Jael::Message(STEAL_FAILED));
		}
	} elsif ($type == STEAL_SUCCESS) {
		my $task_id = $message->get_task_id();
		my $machine_id = $self->{dht}->get_dht_id_for_task($task_id);
		$self->{server}->send($machine_id, new Jael::Message(TASK_STOLEN, $task_id));
		die 'TODO';
	} elsif ($type == STEAL_FAILED) {
		die 'TODO';
	} elsif ($type == TASK_STOLEN) {
		my $task_id = $message->get_task_id();
		my $sender_id = $message->get_sender_id();
		$self->{dht}->set_machine_owning($task_id, $sender_id);
	} elsif ($type == FORK_REQUEST) {
		my $task_id = $message->get_task_id();
		my $fork_ok = $self->{dht}->fork($task_id);
		my $sender_id = $message->get_sender_id();
		if ($fork_ok) {
			$self->{server}->send($sender_id, new Jael::Message(FORK_ACCEPTED, $task_id));
		} else {
			$self->{server}->send($sender_id, new Jael::Message(FORK_REFUSED, $task_id));
		}
	} elsif ($type == FORK_ACCEPTED) {
		die 'TODO';
	} elsif ($type == FORK_REFUSED) {
		die 'TODO';
	} elsif ($type == FILE_REQUEST) {
		my $task_id = $message->get_task_id();
		my $sender_id = $message->get_sender_id();
		$self->{server}->send_file($sender_id, $task_id);
	} else {
		die "unknown message $message";
	}
}

1;
