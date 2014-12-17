#!/usr/bin/env perl

use strict;
use warnings;
use Jael::Message;
use Jael::MessageBuffers;

my $msg1 = new Jael::Message(END_ALL);
$msg1->set_sender_id(0);
my $msg2 = new Jael::Message(TASK_COMPUTATION_COMPLETED, 5);
$msg2->set_sender_id(0);
my $msg3 = new Jael::Message(TASKGRAPH, "graph", "foobar baz");
$msg3->set_sender_id(2);
my $string = $msg1->pack() . $msg2->pack() . $msg3->pack();
my $bufs = new Jael::MessageBuffers;
$bufs->incoming_data(1, $string);
