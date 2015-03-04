# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::TaskParser;

use strict;
use warnings;

use Jael::RealTask;
use Jael::TaskGraph;
use Jael::Debug;

use constant {
    PARSING_NOTHING => 0,
    PARSING_VARIABLES => 1,
    PARSING_FILES_BEFORE_TARGET => 2,
    PARSING_FILES_COMMAND => 3
};

use constant JAEL_MAKE => "jael_make";

my @handlers = (\&nothing, \&variables, \&before_target, \&command);

sub make {
    my $self = {};
    
    $self->{vars} = {};
    $self->{not_a_target} = 0;
    $self->{tasksgraph} = new Jael::TaskGraph;
    $self->{commands} = [];

    Jael::Debug::msg("launching jael_make\n");
    open(MAKE, JAEL_MAKE . " -t -p |") or die "unable to fork jael_make : $!";
    $self->{state} = PARSING_NOTHING;
    
    my $line;
    
    while($line = <MAKE>) {
        chomp($line);
        $handlers[$self->{state}]->($self, $line);
    }
    
    close(MAKE);
    Jael::Debug::msg("jael_make completed\n");
    Jael::Debug::msg("tasks :\n $self->{tasksgraph}\n");

    if (defined $self->{vars}->{'.DEFAULT_GOAL'}) {
        $self->{tasksgraph}->set_main_target($self->{vars}->{'.DEFAULT_GOAL'});
    }
    
    return $self->{tasksgraph};
}

sub nothing {
    my $self = shift;
    my $line = shift;
    
    if ($line=~/jael_make_wrapper directory is '([^']+)'/) {
        $self->{current_directory} = $1;
    }
    
    if ($line eq '# Variables') {
        $self->{state} = PARSING_VARIABLES;
    }
    
    if ($line eq '# Files') {
        $self->{state} = PARSING_FILES_BEFORE_TARGET;
    }

    return;
}

sub variables {
    my $self = shift;
    my $line = shift;
    
    if ($line =~/^(\S+)\s=\s(\S+)/) {
        $self->{vars}->{$1} = $2;
    }
    
    if ($line eq '# variable set hash-table stats:') {
        $self->{state} = PARSING_NOTHING;
    }

    return;
}

sub before_target {
    my $self = shift;
    my $line = shift;
    
    if ($line =~/^(\S+):(.*)?$/) {
        $self->{current_target} = $1;
        $self->{current_deps} = $2;
        $self->{state} = PARSING_FILES_COMMAND;
    }
    
    if ($line eq '# files hash-table stats:') {
        $self->{state} = PARSING_NOTHING;
    }

    if ($line eq '# Not a target:') {
        $self->{not_a_target} = 1;
    }

    return;
}

sub command {
    my $self = shift;
    my $line = shift;
    
    if ($line=~/^#/) {
        return;
    }
    
    if ($line eq '') {
        my $command = join("\n", @{$self->{commands}});
        
        $command = replace_variables($self, $command, 0);
        
        my $task = Jael::RealTask->new($self->{current_target}, $command, $self->{current_deps});
        
        unless ($self->{not_a_target}) {
            $self->{tasksgraph}->add_task($task);
        }
        
        #reset variables
        @{$self->{commands}} = ();
        $self->{not_a_target} = 0;
        $self->{state} = PARSING_FILES_BEFORE_TARGET;
    } elsif ($line =~/\t(.+)$/) {
        push @{$self->{commands}}, $1;
    } else {
        die "unknown command line $line";
    }

    return;
}

sub replace_variables {
    my $self = shift;
    my $command = shift;
    my $recursion_level = shift;
    my %tokens;
    #we match $(...)
    #but we need to start with the inner ones
    #$(....$(...)...)
    my $regex = qr/
         (
		 \$\(
			(?:
				(?:(?:\$[^(])|(?:[^$()]))++
				|
				(?1)
			)*
		 \)
		 )
	/x;
    my @top_substrings = $command =~ m/$regex/g;
    
    for my $substring (@top_substrings) {
        my $substring_content = $substring;
    
        $substring_content =~s/^\$\(//;
        $substring_content =~s/\)$//;
        
        my $substituted_substring = replace_variables($self, $substring_content, $recursion_level+1);
        
        $command =~s/\Q$substring\E/$substituted_substring/;
    }
    
    return $command if $recursion_level == 0;
    
    if (exists $self->{vars}->{$command}) {
        return $self->{vars}->{$command};
    } else {
        return "\$($command)";
    }

    return;
}

1;
