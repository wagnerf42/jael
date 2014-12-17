package Jael::Stack;

sub new {
	my $class = shift;
	my $self = {};
	$self->{tasks} = [];
	bless $self, $class;
	return $self;
}

1;
