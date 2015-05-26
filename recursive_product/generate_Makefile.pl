#!/usr/bin/env perl

use strict;
use warnings;

die 'give max recursion level' unless defined $ARGV[0] and $ARGV[0]=~/^\d+$/;

print <<HDOC;
all: c check

check: a b
	matrix_multiply.pl a b check
HDOC

my $recursion_level = $ARGV[0];
my %targets = ('check' => 1);
compute_product('a', 'b', 'c', $recursion_level, \%targets);

print "clean:\n\trm -f ".join(' ', keys %targets)."\n";


sub compute_product {
	my ($in1, $in2, $out, $recursion_level, $targets) = @_;
	$targets->{$out} = 1;
	if ($recursion_level == 0) {
		print "$out: $in1 $in2\n";
		print "\tmatrix_multiply.pl $in1 $in2 $out\n";
	} else {
		generate_split_tasks($in1, $targets);
		generate_split_tasks($in2, $targets);
		generate_subresult("$out-0", "$in1-0", "$in2-0", "$in1-1", "$in2-2", $recursion_level-1, $targets);
		generate_subresult("$out-1", "$in1-0", "$in2-1", "$in1-1", "$in2-3", $recursion_level-1, $targets);
		generate_subresult("$out-2", "$in1-2", "$in2-0", "$in1-3", "$in2-2", $recursion_level-1, $targets);
		generate_subresult("$out-3", "$in1-2", "$in2-1", "$in1-3", "$in2-3", $recursion_level-1, $targets);
		my $subfiles = join(' ', map {"$out-$_"} (0..3));
		print "$out: $subfiles\n";
		print "\tmatrix_fuse.pl $out $subfiles\n";
	}
	return;
}

sub generate_subresult {
	my ($target, $a1, $b1, $a2, $b2, $recursion_level, $targets) = @_;
	compute_product($a1, $b1, "tmp1-$target", $recursion_level, $targets);
	compute_product($a2, $b2, "tmp2-$target", $recursion_level, $targets);
	print "$target: tmp1-$target tmp2-$target\n";
	$targets->{$target} = 1;
	print "\tmatrix_add.pl tmp1-$target tmp2-$target $target\n";
	return;
}

sub generate_split_tasks {
	my $big_file = shift;
	my $targets = shift;
	return if exists $targets->{"split-$big_file"}; #do not re-split if someone else did it
	print ".PHONY: split-$big_file\n";
	print "split-$big_file: $big_file\n";
	$targets->{"split-$big_file"} = 1;
	print "\tmatrix_split.pl $big_file\n";
	my @small_files = map {"$big_file-$_"} (0..3);
	for my $small_file (@small_files) {
		print "$small_file : split-$big_file\n";
		$targets->{$small_file} = 1;
		print "\t\n";
	}
	return @small_files;
}

