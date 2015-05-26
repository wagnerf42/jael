#!/usr/bin/env perl

use strict;
use warnings;
use Matrix;

die 'needed args : input1 input2 output' unless defined $ARGV[2] and -f $ARGV[0] and -f $ARGV[1];

my $a = Matrix->load($ARGV[0]);
my $b = Matrix->load($ARGV[1]);
my $c = $a * $b;
$c->save($ARGV[2]);
