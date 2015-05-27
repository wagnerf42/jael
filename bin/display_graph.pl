#!/usr/bin/env perl

use strict;
use warnings;
use Jael::TasksParser;

die 'give make -t -p log file !' unless defined $ARGV[0] and -f $ARGV[0];

my $tasks = Jael::TasksParser::make($ARGV[0]);
Jael::TasksGraph::display();
