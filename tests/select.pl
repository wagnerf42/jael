use IO::Select;
use IO::Socket;
$lsn = IO::Socket::INET->new(Listen => 1, LocalPort => 8080);
$sel = IO::Select->new( $lsn );
while(@ready = $sel->can_read) {
	foreach $fh (@ready) {
		if($fh == $lsn) {
# Create a new socket
			$new = $lsn->accept;
			$sel->add($new);
		}
		else {
# Process socket
# Maybe we have finished with the socket
			my $buffer = <$fh>;
			print STDERR "reading : $buffer\n";
			$sel->remove($fh);
			$fh->close;
		}
	}
}
