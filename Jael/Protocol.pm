# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Protocol;

# This package handles protocol logic
# How to react on incoming messages

use strict;
use warnings;
use threads;

use Jael::Message;
use Jael::Task;
use Jael::VirtualTask;
use Jael::Dht;
use Jael::Paje;
use Jael::TasksGraph;

use Data::Dumper; # TMP

# Make a new protocol
# Parameters: ExecutionEngine, Server
sub new {
    my $class = shift;
    my $self = {};

    my $execution_engine = shift;
    my $server = shift;

    $self->{id} = $execution_engine->get_id();
    $self->{dht} = Jael::Dht->new($self->{id});
    $self->{tasks_stack} = $execution_engine->get_tasks_stack();
    $self->{fork_set} = $execution_engine->get_fork_set();
    $self->{steal_authorized} = $execution_engine->get_steal_variable();
    $self->{server} = $server;

    bless $self, $class;

    return $self;
}

sub ask_for_files {
    my $self = shift;
    my $task = shift;
    my $task_id = $task->get_id();
    my $dependencies = Jael::TasksGraph::get_dependencies($task_id);
    my $is_ready = 1;
    my @missing_files;

    for my $dependency (@{$dependencies}) {
        # One or more files are missing
        if (not -e $dependency) {
            push @missing_files, $dependency;
            my $dht_owner = Jael::Dht::hash_task_id($dependency);

            Jael::Debug::msg('protocol', "[Protocol]Missing dependency for task $task_id : $dependency");

            $self->{server}->send($dht_owner, Jael::Message->new($Jael::Message::DATA_LOCALISATION, $dependency));
            $is_ready = 0;
        }
    }

    Jael::Debug::msg('task', "asking for files for $task_id ; deps are @$dependencies ; missing is @missing_files");

    if ($is_ready) {
        Jael::Debug::msg('task', "[Protocol]task $task_id is now ready");
        $task->update_status($Jael::Task::TASK_STATUS_READY);
    } else {
        $task->update_status($Jael::Task::TASK_STATUS_READY_WAITING_FOR_FILES);
    }

    return;
}

sub incoming_message {
    my $self = shift;
    my $message = shift;

    my $type = $message->get_type();
    my $sender_id = $message->get_sender_id();

    Jael::Debug::msg('network', "[Protocol]incoming_message type: $type");

    # -----------------------------------------------------------------
    # Task computation ok : Update Dht status and inform machines
    # -----------------------------------------------------------------
    if ($type == $Jael::Message::TASK_COMPUTATION_COMPLETED) {
        my $task_id = $message->get_task_id();

        my $machine_which_completed_task = $message->get_machines_list()->[0];
        Jael::Debug::msg('dht', "we are informed that $task_id completed on machine $machine_which_completed_task");
        # $sender_id is an owner of the data's $task_id
        $self->{dht}->add_data_owner($task_id, $machine_which_completed_task);

        # Get machines depending on $task_id
        my @machines_to_inform = $self->{dht}->compute_dht_owners_for_tasks_depending_on($task_id);

        # Send to DHT_OWNER($task_id) : '$task_id completed'
        my $message = Jael::Message->new($Jael::Message::REVERSE_DEPENDENCIES_UPDATE_TASK_COMPLETED, $task_id, $machine_which_completed_task);

        for my $machine_id (@machines_to_inform) {
			Jael::Debug::msg('dht', "forwarding completion information of $task_id to $machine_id");
            $self->{server}->send($machine_id, $message);
        }
    }

    # -----------------------------------------------------------------
    # One task completed : Update reverse dependencies status
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::REVERSE_DEPENDENCIES_UPDATE_TASK_COMPLETED) {
        my $task_id = $message->get_task_id();
        my $machine_which_completed_task = $message->get_machines_list()->[0];

        # We get ready reverse dependencies
        my $ready_tasks_ids = $self->{dht}->update_reverse_dependencies_status($task_id);
        Jael::Debug::msg('dht', "we are informed for deps that $task_id completed on machine $machine_which_completed_task ; " .
                         "tasks turning ready are @$ready_tasks_ids");

        for my $ready_task_id (@{$ready_tasks_ids}) {
            if (Jael::TasksGraph::is_file_transfer_task($ready_task_id)) {
                # file tasks never become READY
                # they directly reach the COMPLETED status
                $self->{server}->send($self->{id}, Jael::Message->new($Jael::Message::TASK_COMPUTATION_COMPLETED, $ready_task_id,
                                                                      $machine_which_completed_task));
            } else {
                my $machine_id = $self->{dht}->get_machine_owning($ready_task_id);
                $self->{server}->send($machine_id, Jael::Message->new($Jael::Message::REVERSE_DEPENDENCIES_UPDATE_TASK_READY,
                                                                      $ready_task_id));
            }
        }
    }

    # -----------------------------------------------------------------
    # We have a new ready task waiting for files
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::REVERSE_DEPENDENCIES_UPDATE_TASK_READY) {
        my $task_id = $message->get_task_id();

        # Set $TASK_STATUS_READY if there is no dependency problems
        $self->{tasks_stack}->apply_function_on_task($task_id, \&ask_for_files, $self);
    }

    # -----------------------------------------------------------------
    # DHT_OWNER(task_i) gives the data localisation list of task_i
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::DATA_LOCALISATION) {
        my $task_id = $message->get_task_id();
        my $machines = $self->{dht}->get_data_owners($task_id);

        $self->{server}->send($sender_id, Jael::Message->new($Jael::Message::DATA_LOCATED, $task_id, @{$machines}));
    }

    # -----------------------------------------------------------------
    # We received the machines owners of task_i data
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::DATA_LOCATED) {
        my $task_id = $message->get_task_id();
        my $machines = $message->get_machines_list();
        Jael::Debug::msg('protocol', "data located for $task_id on machines @$machines");
        my $destination = ${$machines}[int(rand(scalar @{$machines}))];

        Jael::Debug::msg('protocol', "asking for data $task_id to machine $destination");
        $self->{server}->send($destination, Jael::Message->new($Jael::Message::FILE_REQUEST, $task_id));
    }

    # -----------------------------------------------------------------
    # process_i says to DHT_OWNER(task_i) 'I have data of task_i'
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::DATA_DUPLICATED) {
        my $task_id = $message->get_task_id();

        $self->{dht}->add_data_owner($task_id, $sender_id);
    }

    # -----------------------------------------------------------------
    # Computation end : Wait/kill threads & exit
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::END_ALL) {
        # There are no more tasks, exiting process
        Jael::Debug::msg('big_event', '[Protocol]we stop now');

        # Kill threads server
        $self->{server}->kill_sending_threads();

        # Waiting all threads (except server threads)
        for my $thr (threads->list()) {
            $thr->kill('SIGUSR1');
            $thr->join();
        }

        # TMP
        Jael::Debug::msg('dht', Data::Dumper->Dump([$self->{dht}]));

        Jael::Paje::destroy_thread();
        Jael::Paje::destroy_process();

        # Done, main thread
        exit 0;
    }

    # -----------------------------------------------------------------
    # Process_i try to steal random task on process_j
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::STEAL_REQUEST) {
        my $task = $self->{tasks_stack}->steal_task(); # Get task, NOT task id here

        if (defined $task) {
            my $task_id = $task->get_id();

            Jael::Debug::msg('protocol', "[Protocol]we authorize $sender_id to steal us of task $task_id");
            Jael::Paje::create_link($Jael::Message::STEAL_SUCCESS, $sender_id, $task_id);

            $self->{server}->send($sender_id, Jael::Message->new($Jael::Message::STEAL_SUCCESS, $task_id));
        } else {
            Jael::Paje::create_link($Jael::Message::STEAL_FAILED, $sender_id);
            Jael::Debug::msg('protocol', "[Protocol]we don't authorize $sender_id to steal us");
            $self->{server}->send($sender_id, Jael::Message->new($Jael::Message::STEAL_FAILED));
        }
    }

    # -----------------------------------------------------------------
    # Process_i steal a new task => Update tasks stack
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::STEAL_SUCCESS) {
        my $task_id = $message->get_task_id();

        Jael::Debug::msg('protocol', "[Protocol]steal success on $sender_id, new task on stack : $task_id");
        Jael::Paje::destroy_link($Jael::Message::STEAL_SUCCESS, $sender_id, $task_id);

        my $task = Jael::TasksGraph::get_task($task_id);

        # We have stolen one real task
        unless ($task_id =~ /^$VIRTUAL_TASK_PREFIX/) {
            # Notify DHT 'I have pushed a new task'
			# TODO TODO : why exactly do we need this message ?
			# TODO : remove it ?
            my $message = Jael::Message->new($Jael::Message::TASK_IS_PUSHED, $task_id);
            my $destination = Jael::Dht::hash_task_id($task_id);

            # Set $TASK_STATUS_READY if there is no dependency problems
            $self->ask_for_files($task);
            $self->{tasks_stack}->push_task($task);
            $self->{server}->send($destination, $message);
        }
        # We have stolen one virtual task
        else {
            $self->{tasks_stack}->push_task($task);
        }

        lock($self->{steal_authorized});
        ${$self->{steal_authorized}} = 1;
    }

    # -----------------------------------------------------------------
    # Process_i failed to steal a new task
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::STEAL_FAILED) {
        Jael::Debug::msg('protocol', "[Protocol]steal fail on $sender_id");
        Jael::Paje::destroy_link($Jael::Message::STEAL_FAILED, $sender_id);

        lock($self->{steal_authorized});
        ${$self->{steal_authorized}} = 1;
    }

    # -----------------------------------------------------------------
    # DHT_OWNER(task_i) knows task_i is a task of process_j
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::TASK_IS_PUSHED) {
        my $task_id = $message->get_task_id();

        Jael::Debug::msg('dht', "[Protocol]task $task_id is on the stack of process $sender_id");
        $self->{dht}->set_machine_owning($task_id, $sender_id);
    }

    # -----------------------------------------------------------------
    # process_j fork request task_i to DHT_OWNER(task_i)
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::FORK_REQUEST) {
        my $task_id = $message->get_task_id(); # task_i
		die unless $task_id =~/^$Jael::VirtualTask::VIRTUAL_TASK_PREFIX(.*)/;
		my $real_task_id = $1;

        # Fork success
        if ($self->{dht}->fork_request($real_task_id, $sender_id)) {
            Jael::Debug::msg('fork', "[Protocol]task $task_id is forked by $sender_id");
            Jael::Paje::create_link($Jael::Message::FORK_ACCEPTED, $sender_id, $task_id);

            my $completed_dependencies = $self->{dht}->get_completed_dependencies($task_id, $sender_id);
            #TODO: clarify delimiter and escape codes
            my $dependencies = join('&', @$completed_dependencies);
			#TODO: factorize them all
			$self->{dht}->set_machine_owning($real_task_id, $sender_id);
            $self->{server}->send($sender_id, Jael::Message->new($Jael::Message::FORK_ACCEPTED, $task_id, $dependencies));
        }
        # Fork failure
        else {
            Jael::Debug::msg('fork', "[Protocol]task $task_id is not forked by $sender_id");
            $self->{server}->send($sender_id, Jael::Message->new($Jael::Message::FORK_REFUSED, $task_id));
        }
    }

    # -----------------------------------------------------------------
    # Virtual/Real task_i is forked by current process
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::FORK_ACCEPTED) {
        my $task_id = $message->get_label();
        my $task = Jael::TasksGraph::get_task($task_id);

        Jael::Paje::destroy_link($Jael::Message::FORK_ACCEPTED, $sender_id, $task_id);

        my $completed_dependencies = [split('&', $message->get_string())];
        my $tasks_inside_forked_virtual = $task->generate_tasks($completed_dependencies);

        $self->{fork_set}->set_done_status($task_id);

        Jael::Debug::msg('fork', "[Protocol]fork accepted, new task on stack : $task_id with completed dependencies : " .
                         join(',', @{$completed_dependencies}));

        # Notify we have one real task on stack
        my $real_task_created = $tasks_inside_forked_virtual->[-1];
        my $real_task_id = $real_task_created->get_id();

        $self->ask_for_files($real_task_created) if $real_task_created->get_status() == $Jael::Task::TASK_STATUS_READY_WAITING_FOR_FILES;
        $self->{tasks_stack}->push_task(@{$tasks_inside_forked_virtual});

        my $dht_owner = Jael::Dht::hash_task_id($real_task_id);

		# $self->{server}->send($dht_owner, Jael::Message->new($Jael::Message::TASK_IS_PUSHED, $real_task_id));
    }

    # -----------------------------------------------------------------
    # Virtual task_i is not forked by current process
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::FORK_REFUSED) {
        my $task_id = $message->get_task_id();
        $self->{fork_set}->set_done_status($task_id);
    }

    # -----------------------------------------------------------------
    # process_j send file for process_i which waiting
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::FILE_REQUEST) {
        my $filename = $message->get_task_id();
        my $message = Jael::Message->new_file($filename);
        Jael::Debug::msg('protocol', "we have been asked file $filename by $sender_id");
        $self->{server}->send($sender_id, $message);
    }

    elsif ($type == $Jael::Message::FILE) {
        my $filename = $message->get_label();
        my $content = $message->get_string();

        Jael::Debug::msg('protocol', "we received file $filename sent by $sender_id");
        open(my $fh, '>', $filename) or die "Can't open file '$filename' : $!";
        print $fh $content;
        close $fh;

        # We have data and we try to update the stack's status
        $self->{server}->send(Jael::Dht::hash_task_id($filename), Jael::Message->new($Jael::Message::DATA_DUPLICATED, $filename));
        $self->{tasks_stack}->set_ready_status_if_necessary($filename);
    }

    # -----------------------------------------------------------------
    # Taskgraph is received
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::TASKGRAPH) {
        Jael::Debug::msg('big_event', "[Protocol]taskgraph is received");
        Jael::TasksGraph->initialize_by_message($message->get_string());
    }

    # -----------------------------------------------------------------
    # Last file => DONE
    # -----------------------------------------------------------------
    elsif ($type == $Jael::Message::LAST_FILE) {
        Jael::Paje::destroy_thread();
        Jael::Paje::destroy_process();

        exit(0);
    }

    # -----------------------------------------------------------------
    # UNKNOWN MESSAGE
    # -----------------------------------------------------------------
    else {
        die "unknown message $message";
    }

    return;
}

1;

