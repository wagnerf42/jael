package Matrix;

use strict;
use warnings;

use overload
	'+' => \&plus,
	'*' => \&multiply,
	'""' => \&stringify;

sub new {
	my $class = shift;
	my $self = {};
	$self->{lines_number} = shift;
	$self->{columns_number} = shift;
	bless $self, $class;
	return $self;
}

sub load {
	my $class = shift;
	my $filename = shift;
	my $self = {};
	open(my $fd, '<', $filename) or die "cannot open $filename";
	my $head = <$fd>;
	die "invalid header $head" unless $head =~ /^(\d+) (\d+)\n$/;
	($self->{lines_number}, $self->{columns_number}) = ($1, $2);
	$self->{matrix} = [];
	for my $i (0..($self->{lines_number}-1)) {
		my $line = <$fd>;
		die "not enough lines" unless defined $line;
		chomp($line);
		my @line = split(' ', $line);
		die "wrong line size : ".(scalar @line)." instead of expected $self->{columns_number}" unless $self->{columns_number} == @line;
		push @{$self->{matrix}}, \@line;
	}
	close($fd);
	bless $self, $class;
	return $self;
}

sub plus {
	my $a = shift;
	my $b = shift;
	die 'wrong number of lines' unless $a->{lines_number} == $b->{lines_number};
	die 'wrong number of columns' unless $a->{columns_number} == $b->{columns_number};
	my $c = Matrix->new($a->{lines_number}, $a->{columns_number});
	for my $i (0..($a->{lines_number}-1)) {
		for my $j (0..($a->{columns_number}-1)) {
			$c->{matrix}->[$i][$j] = $a->{matrix}->[$i][$j] + $b->{matrix}->[$i][$j];
		}
	}
	return $c;
}

sub multiply {
	my $a = shift;
	my $b = shift;
	die 'wrong sizes' unless $a->{columns_number} == $b->{lines_number};
	my $c = Matrix->new($a->{lines_number}, $b->{columns_number});
	for my $i (0..($a->{lines_number}-1)) {
		for my $j (0..($b->{columns_number}-1)) {
			my $s = 0;
			for my $k (0..($a->{columns_number}-1)) {
				$s += $a->{matrix}->[$i][$k] * $b->{matrix}->[$k][$j];
			}
			$c->{matrix}->[$i][$j] = $s;
		}
	}
	return $c;
}

#fuse b into a
sub fuse {
	my $a = shift;
	my $b = shift;
	my $line_offset = shift;
	my $column_offset = shift;
	for my $i (0..($b->{lines_number}-1)) {
		my $adjusted_i = $i + $line_offset;
		for my $j (0..($b->{columns_number}-1)) {
			my $adjusted_j = $j + $column_offset;
			$a->{matrix}->[$adjusted_i][$adjusted_j] = $b->{matrix}->[$i][$j];
		}
	}
	return;
}

sub stringify {
	my $self = shift;
	my @lines;
	for my $i (0..($self->{lines_number}-1)) {
		my $line = $self->{matrix}->[$i];
		my @values;
		for my $j (0..($self->{columns_number}-1)) {
			my $value;
			if (defined $line) {
				$value = $line->[$j];
			}
			$value = 'x' unless defined $value;
			push @values, $value;
		}
		push @lines, join(' ', @values);
	}
	return "$self->{lines_number} x $self->{columns_number} => [\n".join("\n", @lines)." ]\n";
}

sub save {
	my $self = shift;
	my $filename = shift;
	open(my $fd, '>', $filename) or die "cannot save $filename";
	print $fd "$self->{lines_number} $self->{columns_number}\n";
	for my $line (@{$self->{matrix}}) {
		unless (defined $line) {
			die 'undefined line';
		}
		print $fd join(' ', @{$line})."\n";
	}
	close($fd);
	return;
}

sub save_submatrix {
	my $self = shift;
	my $i_offset = shift;
	my $j_offset = shift;
	my $lines_number = shift;
	my $columns_number = shift;
	my $filename = shift;
	open(my $fd, '>', $filename) or die "cannot save $filename";
	print $fd "$lines_number $columns_number";
	for my $i (0..($lines_number-1)) {
		print $fd "\n";
		my $line = $self->{matrix}->[$i + $i_offset];
		print $fd join(' ', @{$line}[$j_offset..($j_offset+$columns_number-1)]);
	}
	close($fd);
	return;
}

1;
