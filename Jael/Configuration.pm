package Jael::Configuration;

use strict;
use warnings;

sub new {
	my $class = shift;
	my $self = {};
	my $config_file = "$ENV{HOME}/.jaelrc";
	if (-f $config_file) {
		open(CONFIG, "< $config_file") or die 'unable to open configuration file';
		my $key;
		while (my $line = <CONFIG>) {
			next if $line =~/^#/;
			if ($line =~ /^machines:\s*$/) {
				$key = 'machines';
				$self->{$key} = [];
			} elsif ($line =~ /\t\s*-\s*(\S+)$/) {
				push @{$self->{$key}}, $1;
			}
		}
		close(CONFIG);
	}
	bless $self, $class;
	return $self;
}

1;
