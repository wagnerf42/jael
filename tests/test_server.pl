#!/usr/bin/env perl

use strict;
use warnings;
use Jael::ServerEngine;

my $server = new Jael::ServerEngine(0, 1, 'havasupai');
$server->run();
