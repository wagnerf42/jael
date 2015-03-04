# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::TaskGraph;

use strict;
use warnings;

use File::Temp;
use overload '""' => \&stringify;
use Jael::Debug;
use Data::Dumper;
use Scalar::Util qw(refaddr);

use Jael::VirtualTask;

use constant IMAGE_VIEWER => 'ristretto';

sub new {
    my $class = shift;
    my $self = {};
    
    $self->{tasks} = {};        # Index of all tasks, indexed by ID
    $self->{dependencies} = {}; # Store for each task what other tasks we need
    
    bless $self, $class;
    
    return $self;
}

sub stringify {
    my $self = shift;
    return join("\n", map {$self->{tasks}->{$_}} (keys %{$self->{tasks}}));
}

sub add_task {
    my $self = shift;
    my $task = shift;
    my $id = $task->get_id();

    die "task $id already there" if exists $self->{tasks}->{$id};
    
    $self->{tasks}->{$id} = $task;
    $self->{dependencies}->{$id} = [$task->get_dependencies()]; 
    
    return;
}

sub get_task {
    my $self = shift;
    return $self->{tasks}->{shift};
}

sub display_graph {
    my $self = shift;

    # Make new temp file for image graph
    my ($dotfile, $dotfilename) = File::Temp::tempfile();
    
    print $dotfile "digraph g {\n";
    
    for my $task (values %{$self->{tasks}}) {
        my $task_name = refaddr $task;
        my $id = $task->get_id();
        
        print $dotfile "n$task_name [label=\"$id\"];\n";

        for my $dep ($task->get_dependencies()) {
            my $task_we_need = $self->{tasks}->{$dep};
            my $needed_name = refaddr $task_we_need;
            
            print $dotfile "n$needed_name -> n$task_name;\n";
        }        
    }
    
    print $dotfile "}\n";
    close($dotfile);

    # Print image with user viewer
    my $img = "$dotfilename.jpg";
    my $viewer = IMAGE_VIEWER;
    
    `dot -Tjpg $dotfilename -o $img`;
    `$viewer $img`;
    
    unlink $img;
    unlink $dotfilename;
    
    return;
}

#remove all useless targets from the graph
sub set_main_target {
    my $self = shift;
    my $main_target = shift;
#    my %useful_targets;
#    Jael::Debug::msg("find useful targets for $main_target\n");
#    find_useful_targets(\%useful_targets, $self->{dependencies}, $main_target);
#    for my $id (keys %{$self->{tasks}}) {
#        unless (exists $useful_targets{$id}) {
#            delete $self->{tasks}->{$id};
#        }
#    }
#    for my $id (keys %{$self->{dependencies}}) {
#        unless (exists $useful_targets{$id}) {
#            delete $self->{dependencies}->{$id};
#        }
#    }
    $self->{main_target} = $main_target;
    return;
}

sub get_main_target {
    my $self = shift;
    return $self->{main_target};
}

# Depth first graph exploration
sub find_useful_targets {
    my $useful_targets = shift;
    my $dependencies = shift;
    my $current_target = shift;
    
    return if exists $useful_targets->{$current_target};
    
    $useful_targets->{$current_target} = 1;
    
    for my $target (@{$dependencies->{$current_target}}) {
        find_useful_targets($useful_targets, $dependencies, $target);
    }

    return;
}

sub generate_reverse_dependencies {
    my $self = shift;
    
    $self->{reverse_dependencies} = {};
    
    for my $task_id (keys %{$self->{tasks}}) {
        # We get the dependencies of the current task
        my $task = $self->{tasks}->{$task_id};
        my @dependencies = $task->get_dependencies();

        # Update the virtuals tasks hierarchy
        for my $dependency (@dependencies) {
            $self->{reverse_dependencies}->{$dependency}->{VIRTUAL_TASK_PREFIX . $task_id} = 1;
        }
    }

    return;
}

sub generate_virtual_tasks {
    my $self = shift;
    
    $self->generate_reverse_dependencies();

    # For each task, we add one virtual task in graph
    for my $task_id (keys %{$self->{tasks}}) {
        # Dependencies of virtual task
        my $dependencies = $self->{reverse_dependencies}->{$task_id};

        # Tasks to generate by virtual task : [virtual A, virtual B ... , real_task_id]
        my $tasks_to_fork = [(map {VIRTUAL_TASK_PREFIX . $_} @{$self->{dependencies}->{$task_id}}), $task_id];
        
        # Update graph state
        my $virtual_task = Jael::VirtualTask->new($task_id, $dependencies, $tasks_to_fork);
        $self->add_task($virtual_task);
    }

    print STDERR Data::Dumper->Dump([$self]);
    
    return;
}

1;
