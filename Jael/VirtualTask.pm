# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::VirtualTask;

use strict;
use warnings;
use overload '""' => \&stringify;
use Readonly;
use base 'Exporter';

use Jael::Task;

# VirtualTask extends Task
use parent 'Jael::Task';

our @EXPORT = qw($VIRTUAL_TASK_PREFIX);

Readonly::Scalar our $VIRTUAL_TASK_PREFIX => 'virtual//';

use Jael::TasksGraph;

# Create a new virtual task defined by one target name and reverse dependencies
sub new {
    my $class = shift;
    my $self = $class->SUPER::new(shift); # Call Task->new with target name

    # It exists normaly at least one task id (real task)
    $self->{reverse_dependencies} = shift;
    $self->{dependencies} = {}; # No dependencies for virtual task

    # Virtual task is always ready
    $self->{status} = $Jael::Task::TASK_STATUS_READY;

    bless $self, $class;
    Jael::Debug::msg('task', "created task {$self}");
    return $self;
}

sub is_real_task_id {
	my $id = shift;
	return (not($id=~/^$VIRTUAL_TASK_PREFIX(.*)/));
}

sub stringify {
    my $self = shift;
    return $VIRTUAL_TASK_PREFIX . "$self->{target_name}: " . join(" ", @{$self->{reverse_dependencies}});
}

# Return always 1
sub is_virtual {
    return 1;
}

# Return the virtual task id
sub get_id {
    my $self = shift;
    return $VIRTUAL_TASK_PREFIX . "$self->{target_name}";
}

# Return the tasks to generate:
# - The 'target name'
# - The reverse dependencies of the real task 'target name' with virtual prefix
sub get_tasks_to_generate {
    my $self = shift;
	# we look at reverse deps
	# any real task is created
	# any non-file virtual task is created
	# for file virtual tasks we recurse on them
	my @created_ids;
	for my $id (@{$self->{reverse_dependencies}}) {
		if (is_real_task_id($id)) {
			push @created_ids, $id;
		} else {
			if (Jael::TasksGraph::is_file_transfer_task($id)) {
				# we add virtual tasks for each dependency
				die unless ($id =~ /^$Jael::VirtualTask::VIRTUAL_TASK_PREFIX(.*)/);
				my $real_task_id = $1;
				my $dependencies = Jael::TasksGraph::get_dependencies($real_task_id);
				push @created_ids, map {"$VIRTUAL_TASK_PREFIX$_"} @$dependencies;
			} else {
				push @created_ids, $id;
			}
		}
	}
	return @created_ids;
}

# Generate all tasks inside virtual one
# returns list of created tasks with real one as last one
sub generate_tasks {
    my $self = shift;
    my $completed_dependencies = shift;
    my @tasks;
    my $real_task;

    for my $task_id ($self->get_tasks_to_generate()) {
        my $task = Jael::TasksGraph::get_task($task_id);

        if ($task->is_virtual()) {
            push @tasks, $task;
        } else {
            $task->unset_dependency($_) for @$completed_dependencies;
            $real_task = $task;
        }
    }

    push @tasks, $real_task;
    Jael::Debug::msg('task', "executed " . $self->get_id() . " ; we generated : " . join(' ', map {$_->get_id()} @tasks));

    return \@tasks;
}

sub unset_dependency {
    #nothing to do for us
    return;
}

1;
