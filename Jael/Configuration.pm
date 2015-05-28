# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Configuration;

use strict;
use warnings;

#TODO: jsonify ??

sub new {
    my $class = shift;
    my $self = {};
    my $config_file = "$ENV{HOME}/.jaelrc";

    if (-f $config_file) {
        open(my $config, '<', $config_file) or die 'unable to open configuration file';
        my $key;

        while (my $line = <$config>) {
            next if $line =~/^#/;
            if ($line =~ /^machines:\s*$/) {
                $key = 'machines';
                $self->{$key} = [];
            } elsif ($line =~ /\t\s*-\s*(\S+)$/) {
                push @{$self->{$key}}, $1;
            } elsif ($line =~ /^max_threads:\s*(\d+)$/) {
				$self->{max_threads} = $1;
			}
            
        }
        close($config);
    }

    bless $self, $class;
    return $self;
}

1;
