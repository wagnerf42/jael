package Jael::TaskGraph;
# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
use File::Temp;
use overload
    '""' => \&stringify;
use Jael::Debug;
use Data::Dumper;
use Scalar::Util qw(refaddr);
use strict;
use warnings;

use constant IMAGE_VIEWER => 'ristretto';

sub new {
    my $class = shift;
    my $self = {};
    $self->{tasks} = {}; #index of all tasks, indexed by ID
    $self->{dependencies} = {}; #store for each task what other tasks we need
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

sub display_graph {
    my $self = shift;
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

#depth first graph exploration
sub find_useful_targets {
    my $useful_targets = shift;
    my $dependencies = shift;
    my $current_target = shift;
    return if exists $useful_targets->{$current_target};
    $useful_targets->{$current_target} = 1;
    for my $target (@{$dependencies->{$current_target}}) {
        find_useful_targets($useful_targets, $dependencies, $target);
    }
}

sub generate_reverse_dependencies {
    my $self = shift;
    
    $self->{reverse_dependencies} = {};
    
    for my $task_id (keys %{$self->{tasks}}) {
        # We get the dependencies of the current task
        my $task = $self->{tasks}->{$task_id};
        my @dependencies = $task->get_dependencies();
        
        for my $dependency (@dependencies) {
            $self->{reverse_dependencies}->{$dependency} = [] unless exists $self->{reverse_dependencies}->{$dependency};
            push @{$self->{reverse_dependencies}->{$dependency}}, $task_id;
        }
    }
}

sub generate_virtual_tasks {
    my $self = shift;
    
    $self->generate_reverse_dependencies();

    # For each task, we add one virtual task in graph
    for my $task_id (keys %{$self->{tasks}}) {
        my $dependencies = $self->{reverse_dependencies}->{$task_id};
        
        print STDERR "DEPS " . join(", ", @{$dependencies}) . "\n";

        my $tasks_to_fork = [ $task_id, map { "virtual:$_" } @{$self->{dependencies}->{$task_id}} ];
        my $virtual_task = Jael::Task->new(Jael::Task::VIRTUAL_TASK, $task_id, $dependencies, $tasks_to_fork);
        
        $self->add_task($virtual_task);
    }

    print STDERR Data::Dumper->Dump([$self]);
    
    return;
}

1;
