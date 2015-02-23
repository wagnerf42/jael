package Jael::Task;
# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
use strict;
use warnings;
use Carp;
use overload
'""' => \&stringify;

our (@ISA, @EXPORT);
BEGIN {
    require Exporter;
    @ISA = qw(Exporter);
    @EXPORT = qw(STATUS_READY STATUS_READY_WAITING_FOR_FILES STATUS_NOT_READY STATUS_FAILED STATUS_COMPLETED);
}

#types of tasks
use constant {
    REAL_TASK => 1, #real program to fork
    VIRTUAL_TASK => 2 #no fork, we only generate new tasks
};

#once in the system, tasks can be in one of the following states :
use constant {
    STATUS_READY => 1, #all dependencies are ok, all files are here => ready to run
    STATUS_READY_WAITING_FOR_FILES => 2, #all dependencies are ok, but waiting for files
    STATUS_NOT_READY => 3, #some dependencies are not computed yet
    STATUS_FAILED => 4, #task executed and failed
    STATUS_COMPLETED => 5 #task executed successfully
};

sub new {
    my $class = shift;
    my $self = {};
    
    $self->{type} = shift;
    $self->{target_name} = shift;
    
    if ($self->{type} == REAL_TASK) {
        $self->{command} = shift;
        my $deps = shift;
    
        if (defined $deps) {
            my @deps = split(/\s+/, $deps);
            $self->{dependencies} = [ grep {$_ ne ''} @deps];
        } else {
            $self->{dependencies} = [];
        }
        
        $self->{path} = shift;
    } elsif ($self->{type} == VIRTUAL_TASK) {
        $self->{dependencies} = shift;
        $self->{tasks_to_generate} = shift;
        $self->{path} = ''; #TODO: ugly, change that
    } else {
        die "Unknown task $self->{type}\n";
    }
    
    bless $self, $class;

    return $self;
}

sub stringify {
    my $self = shift;
    if ($self->{type} == REAL_TASK) {
        return $self->{target_name} . ": " . join(" ", @{$self->{dependencies}}) . "($self->{path})\n\t" . $self->{command} . "\n";
    } else {
        return "virtual:$self->{target_name}: " . join(" ", @{$self->{tasks_to_generate}}) . "\n";
    }
}

sub get_target_name {
    my $self = shift;
    return $self->{target_name};
}

sub get_dependencies {
    my $self = shift;
    
    return map {simplify_path("$self->{path}/$_")} @{$self->{dependencies}};
}

sub get_id {
    my $self = shift;
    return "virtual:$self->{target_name}" if $self->{type} == VIRTUAL_TASK;
    return simplify_path("$self->{path}/$self->{target_name}");
}

sub simplify_path {
    my $string = shift;
    while($string=~/\/\.\./) {
        $string=~s/\/[^\/]+\/\.\.//;
    }
    return $string;
}

1;
