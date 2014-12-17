package Jael::TaskGraph;
use File::Temp;
use overload
	'""' => \&stringify;
use Jael::Debug;
use Data::Dumper;

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
	$self->{dependencies}->{$id} = [] unless exists $self->{dependencies}->{$id};
	for my $dep ($task->get_dependencies()) {
		push @{$self->{dependencies}->{$id}}, $dep;
	}
}

sub display_graph {
	my $self = shift;
	my ($dotfile, $dotfilename) = File::Temp::tempfile();
	my $count = 0;
	my %label;
	for my $target (keys %{$self->{tasks}}) {
		$label{$target} = "n$count";
		$count++;
		my $task = $self->{tasks}->{$target};
		for my $dep ($task->get_dependencies()) {
			$label{$dep} = "n$count";
			$count++;
		}
	}
	print $dotfile "digraph g {\n";
	for my $node (keys %label) {
		print $dotfile $label{$node}."[label=\"$node\"];\n";
	}
	for my $target (keys %{$self->{tasks}}) {
		my $task = $self->{tasks}->{$target};
		for my $dep ($task->get_dependencies()) {
			print $dotfile "$label{$dep} -> $label{$target};\n";
		}
	}
	print $dotfile "}\n";
	close($dotfile);
	my $img = "$dotfilename.jpg";
	`dot -Tjpg $dotfilename -o $img`;
	`geeqie $img`;
	unlink $img;
	unlink $dotfilename;
}

#remove all useless targets from the graph
sub set_main_target {
	my $self = shift;
	my $main_target = shift;
	my %useful_targets;
	Jael::Debug::msg("find useful targets for $main_target\n");
	find_useful_targets(\%useful_targets, $self->{dependencies}, $main_target);
	for my $id (keys %{$self->{tasks}}) {
		unless (exists $useful_targets{$id}) {
			delete $self->{tasks}->{$id};
		}
	}
	for my $id (keys %{$self->{dependencies}}) {
		unless (exists $useful_targets{$id}) {
			delete $self->{dependencies}->{$id};
		}
	}
	$self->{main_target} = $main_target;
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
	for my $task_id (keys %{$self->{tasks}}) {
		my $virtual_task = new Jael::Task(Jael::Task::VIRTUAL_TASK, $task_id, @{$self->{reverse_dependencies}->{$task_id}});
		$self->add_task($virtual_task);
	}
	print STDERR Data::Dumper->Dump([$self]);
}

1;
