#!/usr/bin/env perl

# -------------------------------------------------
# Don't use, old version
# -------------------------------------------------

use strict;
use warnings;
use threads 'exit' => 'threads_only';
use Jael::TasksStack;
    
sub use_stack {
    my $stack = shift;
    my $tid = threads->tid();
    my $elem;

    while ($stack->get_size() > 0) {
        sleep(0.1 + rand(1));
        $elem = $stack->shift_value();

        if (defined $elem) {
            print STDERR "Tid $tid get: $elem\n";            
        } else {
            print STDERR "Tid $tid: No enough data.\n";
        }
        
        $stack->print();
    }    
}

my @tids;
my $stack = Jael::Stack->new();

for my $i (1..10) {
    $stack->push_value($i);
}

# Print init stack
$stack->print();

push(@tids, threads->create(\&use_stack, $stack));
push(@tids, threads->create(\&use_stack, $stack));

foreach my $tid (@tids) {
    $tid->join();
}
