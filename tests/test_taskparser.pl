#!/usr/bin/env perl

use strict;
use warnings;
use Jael::TaskParser;

my $graph = Jael::TaskParser::make();
#$graph->set_main_target('/home/wagnerf/code/jael/bin/test3');
$graph->generate_virtual_tasks();
$graph->display_graph();
