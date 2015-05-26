#!/usr/bin/env perl

use strict;
use warnings;

my $size = $ARGV[0];
$size = 10 unless defined $size;

my @a;
my @b;
my @c;
my @p;

print "all: c check\n\n";

print "check:\ta b\n";
print "\t ./multiply check a b\n";

for my $i (1..$size) {
	for my $j (1..$size) {
		push @a, "a-$i-$j";
		push @b, "b-$i-$j";
		push @c, "c-$i-$j";
		for my $k (1..$size) {
			push @p, "p-$i-$k-$k-$j";
		}
	}
}

print "c:\t@c\n";
print "\t./fuse c $size $size @c\n";

print "\n#\n";

for my $c (@c) {
	my @chars = split(/-/, $c);
	my $i = $chars[1];
	my $j = $chars[2];
	my @deps;
	push @deps, "p-$i-$_-$_-$j" foreach (1..$size);
	print "$c:\t@deps\n";
	print "\t./sum $c @deps\n";
}

print "\n#\n";

for my $p (@p) {
	my @chars = split(/-/, $p);
	my $i = $chars[1];
	my $k = $chars[2];
	my $j = $chars[4];
	print "$p:\ta-$i-$k b-$k-$j\n";
	print "\t./multiply $p a-$i-$k b-$k-$j\n"
}

print "\n#\n";

for my $a (@a) {
	my @chars = split(/-/, $a);
	my $i = $chars[1];
	my $j = $chars[2];
	print "$a:\ta\n";
	print "\t./split $a a $size $size $i $j\n";
}

print "\n#\n";

for my $b (@b) {
	my @chars = split(/-/, $b);
	my $i = $chars[1];
	my $j = $chars[2];
	print "$b:\tb\n";
	print "\t./split $b b $size $size $i $j\n";
}

print "clean:\n";
print "\trm -f @a @b @p @c c check\n";
