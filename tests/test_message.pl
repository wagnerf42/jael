#!/usr/bin/env perl

use strict;
use warnings;
use Jael::Message;

use IO::Socket::INET;

# auto-flush on socket
$| = 1;

my $msg1 = new Jael::Message(END_ALL);
$msg1->set_sender_id(0);
my $msg2 = new Jael::Message(TASK_COMPUTATION_COMPLETED, 5);
$msg2->set_sender_id(0);
my $msg3 = new Jael::Message(TASKGRAPH, "graph", "foobar baz");
$msg3->set_sender_id(2);
my $string = $msg1->pack() . $msg2->pack() . $msg3->pack();

# create a connecting socket
my $socket = new IO::Socket::INET (
	PeerHost => 'localhost',
	PeerPort => '2345',
	Proto => 'tcp',
);
die "cannot connect to the server $!\n" unless $socket;
print "connected to the server\n";

$socket->send($string);
