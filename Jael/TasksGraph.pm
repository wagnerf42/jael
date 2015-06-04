# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::TasksGraph;

use strict;
use warnings;
use overload '""' => \&stringify;
use Readonly;
use threads::shared;
use File::Temp;
use JSON;

use Jael::Debug;
use Jael::VirtualTask;

# Define the image viewer for graph png image
Readonly::Scalar my $IMAGE_VIEWER => 'ristretto';

# Private tasksgraph (singleton)
my $tasksgraph :shared = shared_clone({});

# Initialize the singleton TasksGraph
sub initialize {
    my $class = shift;

    # Store all information for REAL TASKS ONLY
    $tasksgraph->{commands} = shared_clone({}); # To each task id its command
    $tasksgraph->{dependencies} = shared_clone({}); # Store for each task what other tasks we need
    $tasksgraph->{reverse_dependencies} = shared_clone({}); # Store for each task by whom we are needed
    $tasksgraph->{colors} = shared_clone({}); # used for animating log files

    bless $tasksgraph, $class;

    # No direct access to tasks graph
    return;
}

sub colorize_task {
    my $task_id = shift;
    my $color = shift;
    $tasksgraph->{colors}->{$task_id} = $color;
    return;
}

# Initialize the singleton TasksGraph by networking message
sub initialize_by_message {
    my $class = shift;
    my $message = shift;

    $tasksgraph = unserialize($message);

    bless $tasksgraph, $class;

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
    my $buf = decode_json($string);

    return shared_clone($buf);
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
    if ($task_id =~ /^$Jael::VirtualTask::VIRTUAL_TASK_PREFIX(.*)/) {
        my $real_task_id = $1;
        my $dependencies = $tasksgraph->{dependencies}->{$real_task_id};
        my @reverse_virtual_dependencies;

        # The reverse dependencies of one virtual task are equivalent to the task's dependencies with virtual task prefix
        if (defined $dependencies) {
            @reverse_virtual_dependencies = map {$Jael::VirtualTask::VIRTUAL_TASK_PREFIX . $_} @{$dependencies};
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

# Add one real task to tasksgraph
# Note: The virtual tasks are not added directly in tasksgraph
sub add_task {
    my $task_id = shift;

    die "task $task_id already exists" if exists $tasksgraph->{commands}->{$task_id};
    $tasksgraph->{commands}->{$task_id} = shift;

    my $dependencies = shift;
    $tasksgraph->{dependencies}->{$task_id} = shared_clone([]);

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

    # Get a unique integer identifier for each task
    for my $id (sort keys %{$tasksgraph->{commands}}) {
        $nums{$id} = $current_num;
        $current_num++;
    }
    # Get a unique integer identifier for each file
    $current_num = 0;
    my %files_num;
    for my $id (sort keys %{$tasksgraph->{commands}}) {
        for my $dep (sort @{$tasksgraph->{dependencies}->{$id}}) {
            unless (defined $nums{$dep}) {
                $files_num{$dep} = $current_num;
                $current_num++;
            }
        }
    }

    # Generate dot content
    # start with files nodes
    for my $id (sort keys %files_num) {
        print $dotfile "f$files_num{$id}\[color=\"blue\"\, label=\"$id\"];\n";
    }

    #continue with tasks and dependencies
    for my $id (sort keys %{$tasksgraph->{commands}}) {
        my $num = $nums{$id};
        my $color = $tasksgraph->{colors}->{$id};
        if (defined $color) {
            print $dotfile "n$num [style=filled,color=$color,label=\"$id\"];\n";
        } else {
            print $dotfile "n$num [label=\"$id\"];\n";
        }

        for my $dep (sort @{$tasksgraph->{dependencies}->{$id}}) {
            my $dep_num = $nums{$dep};
            if (defined $dep_num) {
                #we depend on a task
                print $dotfile "n$dep_num -> n$num;\n";
            } else {
                #we depend on a file
                print $dotfile "f$files_num{$dep} -> n$num;\n";
            }
        }
    }

    print $dotfile "}\n";
    close($dotfile);

    # Print image with user viewer
    my $img = "$dotfilename.jpg";

    `dot -Tjpg $dotfilename -o $img`;
    if (exists $ENV{IMAGE_VIEWER}) {
        `$ENV{IMAGE_VIEWER} $img`; #security problem
    } else {
        `$IMAGE_VIEWER $img`;
    }

    unlink $img;
    unlink $dotfilename;

    return;
}

# Set the main target
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
    return $Jael::VirtualTask::VIRTUAL_TASK_PREFIX . $tasksgraph->{main_target};
}

# Compute reverse dependencies for each task
sub generate_reverse_dependencies {
    for my $task_id (keys %{$tasksgraph->{commands}}) {
        for my $dependency (@{$tasksgraph->{dependencies}->{$task_id}}) {
            $tasksgraph->{reverse_dependencies}->{$dependency} = shared_clone([]) unless defined $tasksgraph->{reverse_dependencies}->{$dependency};
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

# return true if a task has no command and is only used to transfer files
sub is_file_transfer_task {
    my $task_id = shift;
    $task_id = $1 if ($task_id =~/^$Jael::VirtualTask::VIRTUAL_TASK_PREFIX(.*)/);
    return 1 unless defined $tasksgraph->{commands}->{$task_id};
    return 1 if $tasksgraph->{commands}->{$task_id} eq ''; #TODO: not needed ?
    print STDERR "$task_id is not a file transfer task : command is $tasksgraph->{commands}->{$task_id}\n";
    return 0;
}

sub get_initial_file_transfer_tasks {
    my @tasks;
    my %real_tasks;
    
    for my $task (keys %{$tasksgraph->{commands}}) {
        $real_tasks{$task} = 1;
    }
    
    for my $task (keys %{$tasksgraph->{commands}}) {
        for my $dep (@{$tasksgraph->{dependencies}->{$task}}) {
            push @tasks, $dep unless defined $real_tasks{$dep};
        }
    }
    return @tasks;
}

1;
