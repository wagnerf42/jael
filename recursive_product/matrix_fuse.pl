#!/usr/bin/env perl

use strict;
use warnings;
use Matrix;

die 'needed args : out_file in_top_left in_top_right in_bottom_left in_bottom_right' unless defined $ARGV[4] and -f $ARGV[1] and -f $ARGV[2] and -f $ARGV[3] and -f $ARGV[4];

my @input;
push @input, Matrix->load($ARGV[$_]) for (1..4);

my @i_offsets = (0, 0, $input[0]->{lines_number}, $input[0]->{lines_number});
my @j_offsets = (0, $input[0]->{columns_number}, 0, $input[0]->{columns_number});

my $output = Matrix->new($input[0]->{lines_number} + $input[2]->{lines_number}, $input[0]->{columns_number} + $input[1]->{columns_number});
for my $index (0..$#input) {
	$output->fuse($input[$index], $i_offsets[$index], $j_offsets[$index]);
}
$output->save($ARGV[0]);
