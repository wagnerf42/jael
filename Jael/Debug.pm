# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::Debug;

my $machine_id;
my $machine_name;

sub init {
    $machine_id = shift;
    $machine_name = shift;

    return;
}

sub msg {
    if (exists $ENV{JAEL_DEBUG}) {
        my $msg = shift;
        print STDERR "$machine_id ($machine_name) : $msg\n";
    }
    
    return;
}

sub die {
    my $msg = shift;
    die "$machine_id ($machine_name) : $msg\n";
}

1;
