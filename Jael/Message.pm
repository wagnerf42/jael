# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Message;

# This class provides objects for encoding messages
# Messages can be then packed (turned in binary string)
# or unpacked (back to an object from a string) using
# the corresponding methods
#
# If you want to add a new message type, you need to modify
# new, pack, unpack, stringify

use strict;
use warnings;
use overload '""' => \&stringify;
use Readonly;
use base 'Exporter';
use Jael::ServerEngine;

our @EXPORT = qw($TASK_COMPUTATION_COMPLETED $REVERSE_DEPENDENCIES_UPDATE_TASK_COMPLETED $REVERSE_DEPENDENCIES_UPDATE_TASK_READY
                 $DATA_LOCALISATION $DATA_LOCATED $DATA_DUPLICATED $END_ALL $STEAL_REQUEST $STEAL_FAILED $STEAL_SUCCESS $TASK_IS_PUSHED
                 $FORK_REQUEST $FORK_ACCEPTED $FORK_REFUSED $FILE_REQUEST $FILE $TASKGRAPH $LAST_FILE);

# All types of messages in protocol
Readonly::Scalar our $TASK_COMPUTATION_COMPLETED => 1;
Readonly::Scalar our $REVERSE_DEPENDENCIES_UPDATE_TASK_COMPLETED => 2;
Readonly::Scalar our $REVERSE_DEPENDENCIES_UPDATE_TASK_READY => 3;
Readonly::Scalar our $DATA_LOCALISATION => 4;
Readonly::Scalar our $DATA_LOCATED => 5;
Readonly::Scalar our $DATA_DUPLICATED => 6;
Readonly::Scalar our $END_ALL => 7;
Readonly::Scalar our $STEAL_REQUEST => 8;
Readonly::Scalar our $STEAL_FAILED => 9;
Readonly::Scalar our $STEAL_SUCCESS => 10;
Readonly::Scalar our $TASK_IS_PUSHED => 11;
Readonly::Scalar our $FORK_REQUEST => 12;
Readonly::Scalar our $FORK_ACCEPTED => 13;
Readonly::Scalar our $FORK_REFUSED => 14;
Readonly::Scalar our $FILE_REQUEST => 15;
Readonly::Scalar our $FILE => 16;
Readonly::Scalar our $TASKGRAPH => 17;
Readonly::Scalar our $LAST_FILE => 18;

# Type strings for stringify
my @type_strings = qw(TASK_COMPUTATION_COMPLETED REVERSE_DEPENDENCIES_UPDATE_TASK_COMPLETED REVERSE_DEPENDENCIES_UPDATE_TASK_READY
                      DATA_LOCALISATION DATA_LOCATED DATA_DUPLICATED END_ALL STEAL_REQUEST STEAL_FAILED STEAL_SUCCESS TASK_IS_PUSHED
                      FORK_REQUEST FORK_ACCEPTED FORK_REFUSED FILE_REQUEST FILE TASKGRAPH LAST_FILE);
unshift @type_strings, '';

# What kind of data are associated to each type of message ?
Readonly::Scalar our $TASK_ID => 0;
Readonly::Scalar our $TASK_ID_AND_MACHINES_LIST => 1;
Readonly::Scalar our $NOTHING => 2;
Readonly::Scalar our $LABEL_AND_STRING => 3;

# Links between message type and forma
my @messages_format = qw(-1 1 1 0 0 1 0 2 2 2 0 0 0 3 0 0 3 3 3);

sub new {
    my $class = shift;
    my $self = {};

    $self->{type} = shift;

    if ($messages_format[$self->{type}] == $TASK_ID) {
        $self->{task_id} = shift;
    } elsif ($messages_format[$self->{type}] == $TASK_ID_AND_MACHINES_LIST) {
        $self->{task_id} = shift;
        $self->{machines_ids} = [@_];
    } elsif ($messages_format[$self->{type}] == $LABEL_AND_STRING) {
        $self->{label} = shift;
        $self->{string} = shift;
    }

    bless $self, $class;

    return $self;
}

sub new_file {
	my $class = shift;
	my $filename = shift;
	open(my $fh, '<', $filename) or die "Can't open file '$filename' : $!";
	my $content = do { local $/; <$fh> };
	close($fh);

	my $message = $class->new($FILE, $filename, $content);
	$message->set_priority($Jael::ServerEngine::SENDING_PRIORITY_LOW);
	return $message;
}

sub set_sender_id {
    my $self = shift;
    $self->{sender_id} = shift;
    return;
}

sub get_sender_id {
    my $self = shift;
    return $self->{sender_id};
}

sub set_priority {
    my $self = shift;
    $self->{priority} = shift;
    return;
}

sub get_priority {
    my $self = shift;
    return $self->{priority};
}

sub get_type {
    my $self = shift;
    return $self->{type};
}

sub get_task_id {
    my $self = shift;
    die "no task in $self" unless exists $self->{task_id};
    return $self->{task_id};
}

sub get_label {
    my $self = shift;
    return $self->{label};
}

sub get_string {
    my $self = shift;
    return $self->{string};
}

sub get_machines_list {
    my $self = shift;
    return $self->{machines_ids};
}

sub pack {
    my $self = shift;
    my $string;

    if ($messages_format[$self->{type}] == $TASK_ID) {
        my $task_id_size = length($self->{task_id});
        my $message_size = 12 + $task_id_size;

        $string = pack('N3A*', $message_size, $self->{sender_id}, $self->{type}, $self->{task_id});

    } elsif ($messages_format[$self->{type}] == $TASK_ID_AND_MACHINES_LIST) {
        my $machines_number = @{$self->{machines_ids}};
        my $integer_fields = 4 + $machines_number;
        my $task_id_size = length($self->{task_id});
        my $message_size = $integer_fields * 4 + $task_id_size;

        $string = pack("N4A${task_id_size}N$machines_number", $message_size, $self->{sender_id}, $self->{type},
                       $task_id_size, $self->{task_id}, @{$self->{machines_ids}});

    } elsif ($messages_format[$self->{type}] == $NOTHING) {

        $string = pack('N3', 12, $self->{sender_id}, $self->{type});

    } elsif ($messages_format[$self->{type}] == $LABEL_AND_STRING) {
        my $message_size = 16 + length($self->{label}) + length($self->{string});
        my $label_size = length($self->{label});

        $string = pack('N4A*', $message_size, $self->{sender_id}, $self->{type}, $label_size, "$self->{label}$self->{string}");

    } else {
        die "unknown message type $self";
    }

    # Check it's ok
    my $length = length($string);
    my $size = unpack('N', $string);

    die "wrong packing ($string) for message $self ; size is encoded at $size, should be at $length" unless $size == $length;

    return $string;
}

#TODO: better code factorisation
sub unpack {
    my $string = shift;
    my ($size, $sender_id, $type) = unpack('N3', $string);
    my $unpacked_msg;

    die "wrong message size" unless $size == length($string);

    if ($messages_format[$type] == $TASK_ID) {
        my ($size, $sender_id, $type, $task_id) = unpack('N3A*', $string);

        $unpacked_msg = Jael::Message->new($type, $task_id);
    } elsif ($messages_format[$type] == $TASK_ID_AND_MACHINES_LIST) {
        my ($size, $sender, $type, $task_id_size) = unpack('N4', $string);
        my $task_id;
        my @machines;

        ($size, $sender, $type, $task_id_size, $task_id, @machines) = unpack("N4A${task_id_size}N*", $string);
        $unpacked_msg = Jael::Message->new($type, $task_id, @machines);
    } elsif ($messages_format[$type] == $NOTHING) {
        $unpacked_msg = Jael::Message->new($type);
    } elsif ($messages_format[$type] == $LABEL_AND_STRING) {
        my ($size, $sender, $type, $label_size) = unpack('N4', $string);
        my ($label, $content_string);

        ($size, $sender, $type, $label_size, $label, $content_string) = unpack("N4A${label_size}A*", $string);
        $unpacked_msg = Jael::Message->new($type, $label, $content_string);
    } else {
        die "decoding unknown message type";
    }

    $unpacked_msg->set_sender_id($sender_id);

    return $unpacked_msg;
}

sub stringify {
    my $self = shift;
    my $string;

    if (defined $self->{sender_id}) {
        $string	= "from: $self->{sender_id}";
    } else {
        $string	= "from: UNSET";
    }

    $string .= ", type: $type_strings[$self->{type}]";

    if ($messages_format[$self->{type}] == $TASK_ID) {
        $string .= " : task $self->{task_id}";
    } elsif ($messages_format[$self->{type}] == $TASK_ID_AND_MACHINES_LIST) {
        $string .= " : task $self->{task_id}";
        $string .= " machines [" . join(',', @{$self->{machines_ids}}) . "]";
    } elsif ($messages_format[$self->{type}] == $LABEL_AND_STRING) {
        $string .= " : label : $self->{label} ; string : $self->{string}"
    } elsif ($messages_format[$self->{type}] != $NOTHING) {
        die "unknown message type";
    }

    return $string;
}

1;
