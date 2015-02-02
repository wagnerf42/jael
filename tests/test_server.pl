#!/usr/bin/env perl

use strict;
use warnings;
use Jael::ServerEngine;

my $server = new Jael::ServerEngine(0, 'localhost');
$server->run();
