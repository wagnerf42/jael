# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Protocol;

# This package handles protocol logic
# How to react on incoming messages

use strict;
use warnings;
use threads;

use Jael::Message;
use Jael::Task;
use Jael::Dht;

sub new {
    my $class = shift;
    my $self = {};

    $self->{dht} = shift;
    $self->{tasks_stack} = shift;
    $self->{server} = shift;

    die if not defined $self->{dht};
    bless $self, $class;

    return $self;
}

sub incoming_message {
    my $self = shift;
    my $message = shift;
    my $type = $message->get_type();

    Jael::Debug::msg("incoming_message type: $type");

    # -----------------------------------------------------------------
    # Task computation ok : Update Dht status and inform machines
    # -----------------------------------------------------------------
    if ($type == $Jael::Message::TASK_COMPUTATION_COMPLETED) {
        my $task_id = $message->get_task_id();
        my $sender_id = $message->get_sender_id();

        # Update local status
        $self->{dht}->change_task_status($task_id, $Jael::Dht::DHT_TASK_STATUS_COMPLETED);

        # $sender_id is an owner of the data's $task_id
        $self->{dht}->add_data_owner($task_id, $sender_id);

        # Get machines depending on $task_id
        my @machines_to_inform = $self->{dht}->compute_dht_owners_for_tasks_depending_on($task_id);

        # Send to DHT_OWNER($task_id) : 'ID_TASK completed'
        my $message = Jael::Message->new($Jael::Message::DEPENDENCIES_UPDATE_TASK_COMPLETED, $task_id);

        for my $machine_id (@machines_to_inform) {
            $self->{server}->send($machine_id, $message);
        }
    }

    # -----------------------------------------------------------------
    # One task completed : Update reverse dependencies status
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::DEPENDENCIES_UPDATE_TASK_COMPLETED) {
        my $task_id = $message->get_task_id();

        # We get ready reverse dependencies
        my $ready_tasks_ids = $self->{dht}->update_reverse_dependencies_status($task_id);

        for my $ready_task_id (@{$ready_tasks_ids}) {
            my $machine_id = $self->{dht}->get_machine_owning($ready_task_id);
            $self->{server}->send($machine_id, Jael::Message->new($Jael::Message::DEPENDENCIES_UPDATE_TASK_READY, $ready_task_id));
        }
    } elsif ($type == $Jael::Message::DEPENDENCIES_UPDATE_TASK_READY) {
        #die 'TODO';
        #$self->{stack}->change_task_status($message->get_task_id(), $Jael::Task::TASK_STATUS_READY);
    }

    # -----------------------------------------------------------------
    # DHT_OWNER(task_i) gives the data localisation list of task_i
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::DATA_LOCALISATION) {
        my $task_id = $message->get_task_id();
        my $sender_id = $message->get_sender_id();
        my $machines = $self->{dht}->get_data_owners($task_id);

        $self->{server}->send($sender_id, Jael::Message->new($Jael::Message::DATA_LOCATED, $task_id, @{$machines}));
    } elsif ($type == $Jael::Message::DATA_LOCATED) {
        die 'TODO';
    }

    # -----------------------------------------------------------------
    # process_i says to DHT_OWNER(task_i) 'I have data of task_i'
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::DATA_DUPLICATED) {
        my $task_id = $message->get_task_id();
        my $sender_id = $message->get_sender_id();

        $self->{dht}->add_data_owner($task_id, $sender_id);
    }

    # -----------------------------------------------------------------
    # Computation end : Wait/kill threads & exit
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::END_ALL) {
        # There are no more tasks, exiting process
        Jael::Debug::msg('we stop now');

        # Kill threads server
        $self->{server}->kill_sending_threads();

        # Waiting all threads (except server threads)
        for my $thr (threads->list()) {
            $thr->kill('SIGUSR1');
            $thr->join();
        }

        # Done, main thread
        exit 0;
    }

    # -----------------------------------------------------------------
    # Process_i try to steal random task on process_j
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::STEAL_REQUEST) {
        my $task_id = $self->{tasks_stack}->steal_task();
        my $sender_id = $message->get_sender_id();

        if (defined $task_id) {
            $self->{server}->send($sender_id, Jael::Message->new($Jael::Message::STEAL_SUCCESS, $task_id));
        } else {
            $self->{server}->send($sender_id, Jael::Message->new($Jael::Message::STEAL_FAILED));
        }
    }

    # -----------------------------------------------------------------
    # Process_i steal a new task => Update tasks stack
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::STEAL_SUCCESS) {
        my $task_id = $message->get_task_id();
        $self->{tasks_stack}->push($task_id);
    } elsif ($type == $Jael::Message::STEAL_FAILED) {
        die 'TODO';
    }

    # -----------------------------------------------------------------
    # DHT_OWNER(task_i) knows task_i is a task of process_j
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::TASK_IS_PUSHED) {
        my $task_id = $message->get_task_id();
        my $sender_id = $message->get_sender_id();

        Jael::Debug::msg("task $task_id is on the stack of process $sender_id");
        $self->{dht}->set_machine_owning($task_id, $sender_id);
    }

    # -----------------------------------------------------------------
    # process_j fork request task_i to DHT_OWNER(task_i)
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::FORK_REQUEST) {
        my $task_id = $message->get_task_id();     # task_i
        my $sender_id = $message->get_sender_id(); # process_j

        # Fork success
        if ($self->{dht}->fork_request($task_id, $sender_id)) {
            Jael::Debug::msg("task $task_id is forked by $sender_id");
            $self->{server}->send($sender_id, Jael::Message->new($Jael::Message::FORK_ACCEPTED, $task_id));
        }
        # Fork failure
        else {
            Jael::Debug::msg("task $task_id is not forked by $sender_id");
            $self->{server}->send($sender_id, Jael::Message->new($Jael::Message::FORK_REFUSED, $task_id));
        }
    }

    elsif ($type == $Jael::Message::FORK_ACCEPTED) {
        die 'TODO';
    } elsif ($type == $Jael::Message::FORK_REFUSED) {
        die 'TODO';
    } elsif ($type == $Jael::Message::FILE_REQUEST) {
        die 'TODO';
        # my $task_id = $message->get_task_id();
        # my $sender_id = $message->get_sender_id();
        # $self->{server}->send_file($sender_id, $task_id);
    }

    # -----------------------------------------------------------------
    # Taskgraph is received
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::TASKGRAPH) {
        Jael::Debug::msg("taskgraph is received");
        Jael::TasksGraph->initialize_by_message($message);
    } elsif ($type == $Jael::Message::LAST_FILE) {
        # P0 receives the last file
        #TODO
        exit(0);
    } else {
        die "unknown message $message";
    }

    return;
}

1;
