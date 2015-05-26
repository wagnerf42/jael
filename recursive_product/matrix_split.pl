#!/usr/bin/env perl
use strict;
use warnings;
use Matrix;
use POSIX qw(ceil floor);

die "needed arguments : input_matrix" unless defined $ARGV[0] and -f $ARGV[0];

my $m = Matrix->load($ARGV[0]);

my $big_line = ceil($m->{lines_number}/2);
my $small_line = floor($m->{lines_number}/2);
my @lines_numbers = ($big_line, $big_line, $small_line, $small_line);
my @i_offsets = (0, 0, $big_line, $big_line);

my $big_columns = ceil($m->{columns_number}/2);
my $small_columns = floor($m->{columns_number}/2);
my @columns_numbers = ($big_columns, $small_columns, $big_columns, $small_columns);
my @j_offsets = (0, $big_columns, 0, $big_columns);

for my $index (0..3) {
	$m->save_submatrix($i_offsets[$index], $j_offsets[$index], $lines_numbers[$index], $columns_numbers[$index], "$ARGV[0]-$index");
}
