# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Paje;

use strict;
use warnings;
use Readonly;
use base 'Exporter';
use threads;
use threads::shared;
use Time::HiRes;

our @EXPORT = qw($THREAD_STATUS_EXECUTING $THREAD_STATUS_BLOCKED $THREAD_STATUS_WAITING $THREAD_STATUS_FORKING $THREAD_STATUS_STEALING $THREAD_STATUS_COMPUTING);

Readonly::Scalar our $THREAD_STATUS_EXECUTING => "SE";
Readonly::Scalar our $THREAD_STATUS_BLOCKED => "SB";
Readonly::Scalar our $THREAD_STATUS_WAITING => "SW";

Readonly::Scalar our $THREAD_STATUS_FORKING => "SF";
Readonly::Scalar our $THREAD_STATUS_STEALING => "SS";
Readonly::Scalar our $THREAD_STATUS_COMPUTING => "SC";

my $pid;
my $starting_time;
my $messages_counters_out = shared_clone({});
my $messages_counters_in = shared_clone({});

sub puts {
    my $message = shift;
    return unless $ENV{JAEL_DEBUG} =~ /paje/;
    print("[Paje]$message\n");
    return;
}

sub puts_header {
    # Container --------------------------------------------------------------

    puts('%EventDef PajeDefineContainerType 1');
    puts('%  Name string');
    puts('%  ContainerType string');
    puts('%  Alias string');
    puts('%EndEventDef');

    puts('%EventDef PajeCreateContainer 2');
    puts('%  Time date');
    puts('%  Name string');
    puts('%  Container string');
    puts('%  Type string');
    puts('%  Alias string');
    puts('%EndEventDef');

    puts('%EventDef PajeDestroyContainer 3');
    puts('%  Time date');
    puts('%  Name string');
    puts('%  Type string');
    puts('%EndEventDef');

    # Link -------------------------------------------------------------------

    puts('%EventDef PajeDefineLinkType 4');
    puts('%  Name string');
    puts('%  SourceContainerType string');
    puts('%  DestContainerType string');
    puts('%  ContainerType string');
    puts('%  Alias string');
    puts('%EndEventDef');

    puts('%EventDef PajeStartLink 5');
    puts('%  Time date');
    puts('%  SourceContainer string');
    puts('%  Key string');
    puts('%  Value string');
    puts('%  Container string');
    puts('%  Type string');
    puts('%EndEventDef');

    puts('%EventDef PajeEndLink 6');
    puts('%  Time date');
    puts('%  DestContainer string');
    puts('%  Key string');
    puts('%  Value string');
    puts('%  Container string');
    puts('%  Type string');
    puts('%EndEventDef');

    # State ------------------------------------------------------------------

    puts('%EventDef PajeDefineStateType 7');
    puts('%  Name string');
    puts('%  ContainerType string');
    puts('%  Alias string');
    puts('%EndEventDef');

    puts('%EventDef PajeDefineEntityValue 8');
    puts('%  Name string');
    puts('%  EntityType string');
    puts('%  Color color');
    puts('%  Alias string');
    puts('%EndEventDef');

    puts('%EventDef PajeSetState 9');
    puts('%  Time date');
    puts('%  Value string');
    puts('%  Container string');
    puts('%  Type string');
    puts('%EndEventDef');

    # Event type
    puts('%EventDef PajeDefineEventType 10');
    puts('%  Name string');
    puts('%  ContainerType string');
    puts('%  Alias string');
    puts('%EndEventDef');

    return;
}

sub puts_types {
    # Types
    puts('1 "Process" 0 P');
    puts('1 "Thread" P T');

    # Links
    puts('4 "Task Computation Completed" T T P L1');
    puts('4 "Reverse Dependencies Update Task Completed" T T P L2');
    puts('4 "Reverse Dependencies Update Task Ready" T T P L3');
    puts('4 "Data Localisation" T T P L4');
    puts('4 "Data Located" T T P L5');
    puts('4 "Data Duplicated" T T P L6');
    puts('4 "End All" T T P L7');
    puts('4 "Steal Request" T T P L8');
    puts('4 "Steal Failed" T T P L9');
    puts('4 "Steal Success" T T P L10');
    puts('4 "Task Is Pushed" T T P L11');
    puts('4 "Fork Request" T T P L12');
    puts('4 "Fork Accepted" T T P L13');
    puts('4 "Fork Refused" T T P L14');
    puts('4 "File Request" T T P L15');
    puts('4 "File" T T P L16');
    puts('4 "Taskgraph" T T P L17');
    puts('4 "Last File" T T P L18');

    # Thread's states
    puts('7 "Thread State" T TS');

    puts("8 \"Executing\" TS \"0.0 1.0 0.0\" $THREAD_STATUS_EXECUTING");
    puts("8 \"Blocked\" TS \"0.0 0.0 1.0\" $THREAD_STATUS_BLOCKED");
    puts("8 \"Waiting\" TS \"1.0 0.0 0.0\" $THREAD_STATUS_WAITING");

    puts("8 \"Computing\" TS \"0.0 1.0 0.0\" $THREAD_STATUS_COMPUTING");
    puts("8 \"Forking\" TS \"0.0 0.0 1.0\" $THREAD_STATUS_FORKING");
    puts("8 \"Stealing\" TS \"1.0 0.0 0.0\" $THREAD_STATUS_STEALING");

    return;
}

sub get_elapsed_time {
    return Time::HiRes::time() - $starting_time;
}

sub create_process {
    $pid = shift;
    $starting_time = Time::HiRes::time();

    puts("2 0 \"Process $pid\" 0 P P$pid");

    return;
}

sub destroy_process {
    my $tid = threads->tid();
    my $time = get_elapsed_time();

    puts("3 $time P$pid P");

    return;
}

sub create_thread {
    my $tid = shift;
    my $time = get_elapsed_time();

    puts("2 $time \"Thread $tid\" P$pid T P$pid-T$tid");

    return;
}

sub destroy_thread {
    my $tid = threads->tid();
    my $time = get_elapsed_time();

    puts("3 $time P$pid-T$tid T");

    return;
}

sub generate_message_key {
    my $type = shift;
    my $sender_id = shift;
    my $id = shift;
    my $messages_counters = shift;

    my $message_key = $type . '_' . $sender_id . '_' . $id;

    lock($messages_counters);

    if (not defined $$messages_counters{$message_key}) {
        $$messages_counters{$message_key} = 0;
    } else {
        $$messages_counters{$message_key}++;
    }

    $message_key .= '_' . $$messages_counters{$message_key};

    return $message_key;
}

sub create_link {
    my $type = shift;
    my $sender_id = shift;
    my $label = shift;

    my $tid = threads->tid();
    my $time = get_elapsed_time();

    $label = "" if not defined $label;
    puts("5 $time P$pid-T$tid " . generate_message_key($type, $sender_id, $pid, $messages_counters_out) . " \"$label\" P$pid L$type");

    return;
}

sub destroy_link {
    my $type = shift;
    my $sender_id = shift;
    my $label = shift;

    my $tid = threads->tid();
    my $time = get_elapsed_time();

    $label = "" if not defined $label;
    puts("6 $time P$pid-T$tid " . generate_message_key($type, $pid, $sender_id, $messages_counters_in) . " \"$label\" P$sender_id L$type");

    return;
}

sub set_thread_status {
    my $status = shift;
    my $tid = threads->tid();
    my $time = get_elapsed_time();

    puts("9 $time $status P$pid-T$tid TS");

    return;
}

1;
