#!/usr/bin/env perl

use strict;
use warnings;

die 'please give widht and height' unless defined $ARGV[1] and $ARGV[0]=~/^\d+$/ and $ARGV[1]=~/^\d+$/;
my ($w, $h) = @ARGV;

print "$w $h\n";
for (1..$w) {
	my @line;
	for (1..$h) {
		push @line, int rand(10)+1;
	}
	print "@line\n";
}

