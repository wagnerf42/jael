# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::TasksGraph;

use strict;
use warnings;
use overload '""' => \&stringify;
use Readonly;
use File::Temp;
use JSON;

use Jael::Debug;
use Jael::VirtualTask;

# Define the image viewer for graph png image
Readonly::Scalar my $IMAGE_VIEWER => 'ristretto';

# Private tasksgraph (singleton)
my $tasksgraph;

# Initialize the singleton TasksGraph
sub initialize {
    my $class = shift;
    my $self = {};

    die "tasksgraph is already defined" if defined $tasksgraph;

    # Store all information for REAL TASKS ONLY
    $self->{commands} = {}; # To each task id its command
    $self->{dependencies} = {}; # Store for each task what other tasks we need
    $self->{reverse_dependencies} = {}; # Store for each task by whom we are needed

    bless $self, $class;
    $tasksgraph = $self;

    # No direct access to tasks graph
    return;
}

# Initialize the singleton TasksGraph by networking message
sub initialize_by_message {
    my $class = shift;
    my $message = shift;

    die "tasksgraph is already defined" if defined $tasksgraph;

    my $self = unserialize($message);

    bless $self, $class;
    $tasksgraph = $self;

    # No direct access to tasks graph
    return;
}

# Transforms tasks graph into string
sub serialize {
    # JSON doesn't deal with blessed references => We use a tasksgraph copy
    my %tasksgraph = %{$tasksgraph};
    my $string = encode_json(\%tasksgraph);

    return $string;
}

# Transforms string into tasks graph
sub unserialize {
    my $string = shift;
    my $tasksgraph = decode_json($string);

    return $tasksgraph;
}

# All tasks descriptions
sub stringify {
    my @strings;

    for my $task_id (sort keys %{$tasksgraph->{commands}}) {
        push @strings, "TASK '$task_id': " . join(" ", @{$tasksgraph->{dependencies}->{$task_id}});
        push @strings, $tasksgraph->{commands}->{$task_id} . "\n";
    }

    return join("\n", @strings);
}

# Create one instance of task by task_id
sub get_task {
    my $task_id = shift;
    my $task;

    # Make new virtual task
    if ($task_id =~ /^$VIRTUAL_TASK_PREFIX(.*)/) {
        my $real_task_id = $1;
        my $dependencies = $tasksgraph->{dependencies}->{$real_task_id};
        my @reverse_virtual_dependencies;

        # The reverse dependencies of one virtual task are equivalent to the task's dependencies with virtual task prefix
        if (defined $dependencies) {
            @reverse_virtual_dependencies = map {$VIRTUAL_TASK_PREFIX . $_} @{$dependencies};
        }

        $task = Jael::VirtualTask->new($real_task_id, [$real_task_id, @reverse_virtual_dependencies]);
    } else {
        # Make new real task
        $task = Jael::RealTask->new($task_id, $tasksgraph->{commands}->{$task_id}, $tasksgraph->{dependencies}->{$task_id},
                                    $tasksgraph->{reverse_dependencies}->{$task_id});
        $task->mark_as_main_task() if $task_id eq $tasksgraph->{main_target};
    }

    return $task;
}

# Return 1 if one virtual task must be forked, else 0
sub task_must_be_forked {
    my $task_id = shift;

    if ($task_id =~ /^$VIRTUAL_TASK_PREFIX(.*)/) {
        # One virtual task must be forked if the linked real task has more one reserve dependency
        return (scalar @{$tasksgraph->{reverse_dependencies}->{$1}}) > 1;
    }

    die "$task_id is not one virtual task";
}

# Add one real task to tasksgraph
# Note: The virtual tasks are not added directly in tasksgraph
sub add_task {
    my $task_id = shift;

    die "task $task_id already exists" if exists $tasksgraph->{commands}->{$task_id};
    $tasksgraph->{commands}->{$task_id} = shift;

    my $dependencies = shift;
    $tasksgraph->{dependencies}->{$task_id} = [];

    if (defined $dependencies) {
        my @dependencies = split(/\s+/, $dependencies);

        for my $dependency (grep {$_ ne ''} @dependencies) {
            push @{$tasksgraph->{dependencies}->{$task_id}}, $dependency;
        }
    }

    return;
}

# Display graph with image viewer
sub display {
    # Make new temp file for image graph
    my ($dotfile, $dotfilename) = File::Temp::tempfile();

    print $dotfile "digraph g {\n";

    my %nums;
    my $current_num = 0;

    #get a unique integer identifier for each task
    for my $id (keys %{$tasksgraph->{commands}}) {
        $nums{$id} = $current_num;
        $current_num++;
    }

    #generate dot conten
    for my $id (keys %{$tasksgraph->{commands}}) {
        my $num = $nums{$id};
        print $dotfile "n$num [label=\"$id\"];\n";

        for my $dep (@{$tasksgraph->{dependencies}->{$id}}) {
            my $dep_num = $nums{$dep};
            print $dotfile "n$dep_num -> n$num;\n";
        }
    }

    print $dotfile "}\n";
    close($dotfile);

    # Print image with user viewer
    my $img = "$dotfilename.jpg";

    `dot -Tjpg $dotfilename -o $img`;
    `$IMAGE_VIEWER $img`;

    unlink $img;
    unlink $dotfilename;

    return;
}

# Set the main targe
sub set_main_target {
    die "main target is already defined" if defined $tasksgraph->{main_target};
    $tasksgraph->{main_target} = shift;

    # TODO: remove all useless targets from the graph

    return;
}

# Return the main target or undef if the main target is not defined
sub get_main_target {
    return $tasksgraph->{main_target};
}

# Return the init task id (One virtual task)
sub get_init_task_id {
    return $VIRTUAL_TASK_PREFIX . $tasksgraph->{main_target};
}

# Compute reverse dependencies for each task
sub generate_reverse_dependencies {
    for my $task_id (keys %{$tasksgraph->{commands}}) {
        $tasksgraph->{reverse_dependencies}->{$task_id} = [] unless defined $tasksgraph->{reverse_dependencies}->{$task_id};
        for my $dependency (@{$tasksgraph->{dependencies}->{$task_id}}) {
            push @{$tasksgraph->{reverse_dependencies}->{$dependency}}, $task_id;
        }
    }
    return;
}

# Return the dependencies of one task_id
sub get_dependencies {
    my $task_id = shift;
    return $tasksgraph->{dependencies}->{$task_id};
}

# Return the reverse dependencies of one task_id
sub get_reverse_dependencies {
    my $task_id = shift;
    return $tasksgraph->{reverse_dependencies}->{$task_id};
}

1;
