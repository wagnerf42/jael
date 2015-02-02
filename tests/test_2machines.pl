#!/usr/bin/env perl

use strict;
use warnings;
use threads;
use Jael::ServerEngine;
use Jael::Message;

my $ip = "127.0.0.1";
    
sub exec_machine {
    my $id = shift;
    my $server = new Jael::ServerEngine($id, 'wescoeur-pc', 'localhost');
    $server->send(1-$id, Jael::Message->new(TASK_COMPUTATION_COMPLETED, $id));
    $server->run();
}

my @tids;

push(@tids, threads->create(\&exec_machine, 0));
push(@tids, threads->create(\&exec_machine, 1));

foreach my $tid (@tids) {
    $tid->join();
}
