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
    $self->{server} = shift;

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
    if ($type == TASK_COMPUTATION_COMPLETED) {
        my $task_id = $message->get_task_id();
        my $sender_id = $message->get_sender_id();
        
        # Update local status
        $self->{dht}->change_task_status($task_id, $Jael::Dht::DHT_TASK_STATUS_COMPLETED);

        # $sender_id is an owner of the data's $task_id
        $self->{dht}->add_data_owner($task_id, $sender_id);
            
        # Get machines depending on $task_id
        my @machines_to_inform = $self->{dht}->compute_machines_owning_tasks_depending_on($task_id);

        # Send to DHT_OWNER($task_id) : 'ID_TASK completed'
        my $message = new Jael::Message(DEPENDENCIES_UPDATE_TASK_COMPLETED, $task_id);
        
        for my $machine_id (@machines_to_inform) {
            $self->{server}->send($machine_id, $message);
        }
    }
    
    # -----------------------------------------------------------------
    # One task completed : Update reverse dependencies status
    # -----------------------------------------------------------------
    elsif ($type == DEPENDENCIES_UPDATE_TASK_COMPLETED) {
        my $task_id = $message->get_task_id();

        # We get ready reverse dependencies 
        my $ready_tasks_ids = $self->{dht}->update_reverse_dependencies_status($task_id);
       
        for my $ready_task_id (@{$ready_tasks_ids}) {
            my $machine_id = $self->{dht}->get_machine_owning($ready_task_id);
            $self->{server}->send($machine_id, new Jael::Message(DEPENDENCIES_UPDATE_TASK_READY, $ready_task_id));
        }
    } elsif ($type == DEPENDENCIES_UPDATE_TASK_READY) {
        #die 'TODO';
        #$self->{stack}->change_task_status($message->get_task_id(), $Jael::Dht::TASK_STATUS_READY);
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
    } 

    # -----------------------------------------------------------------
    # Computation end : Wait/kill threads & exit
    # -----------------------------------------------------------------
    elsif ($type == END_ALL) {
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
        #$self->{server}->send($machine_id, new Jael::Message(TASK_STOLEN, $task_id));
        die 'TODO';
    } elsif ($type == STEAL_FAILED) {
        #die 'TODO';
    }
    
    # -----------------------------------------------------------------
    # DHT_OWNER(task_i) knows task_i is a task of process_j
    # -----------------------------------------------------------------
    elsif ($type == TASK_IS_PUSHED) {
        my $task_id = $message->get_task_id();     # task_i
        my $sender_id = $message->get_sender_id(); # process_j

        Jael::Debug::msg("task $task_id is on the stack of process $sender_id");
        $self->{dht}->set_machine_owning($task_id, $sender_id);
    } 

    # -----------------------------------------------------------------
    # process_j fork request task_i to DHT_OWNER(task_i)
    # -----------------------------------------------------------------
    elsif ($type == FORK_REQUEST) {
        my $task_id = $message->get_task_id();     # task_i
        my $sender_id = $message->get_sender_id(); # process_j
 
        # Fork success
        if ($self->{dht}->fork_request($task_id, $sender_id)) {
            Jael::Debug::msg("task $task_id is forked by $sender_id");
            $self->{server}->send($sender_id, new Jael::Message(FORK_ACCEPTED, $task_id));
        } 
        # Fork failure
        else {
            Jael::Debug::msg("task $task_id is not forked by $sender_id");
            $self->{server}->send($sender_id, new Jael::Message(FORK_REFUSED, $task_id));
        }
    }
    
    elsif ($type == FORK_ACCEPTED) {
        die 'TODO';
    } elsif ($type == FORK_REFUSED) {
        die 'TODO';
    } elsif ($type == FILE_REQUEST) {
        my $task_id = $message->get_task_id();
        my $sender_id = $message->get_sender_id();
        $self->{server}->send_file($sender_id, $task_id);
    } 

    # -----------------------------------------------------------------
    # Taskgraph is received
    # -----------------------------------------------------------------
    elsif ($type == TASKGRAPH) {
        Jael::Debug::msg("taskgraph is received");
        Jael::TasksGraph->initialize_by_message($message);
    } elsif ($type == LAST_FILE) {
        # P0 receives the last file
        #TODO
        exit(0);
    } else {
        die "unknown message $message";
    }
}

1;
