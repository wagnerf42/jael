# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
package Jael::MessageBuffers;

use strict;
use warnings;

use Jael::Debug;

sub new {
    my $class = shift;
    my $self = {};
    
    $self->{buffers} = {}; #buffers are indexed by sockets
    bless $self, $class;
    
    return $self;
}

# Returns an unpacked Message or nothing if there are not enough data
sub incoming_data {
    my $self = shift;
    my $socket = shift;
    my $data = shift;
    
    $self->{buffers}->{$socket} = '' unless exists $self->{buffers}->{$socket};
    $self->{buffers}->{$socket} .= $data;

    my @incoming_messages;
    while (length($self->{buffers}->{$socket}) >= 4) { #while enough data is here to read message size
        my $size = unpack('N', $self->{buffers}->{$socket});
    
        if ($size <= length($self->{buffers}->{$socket})) { #message is received in its entirety
            my $message_string = substr($self->{buffers}->{$socket}, 0, $size, ''); #this removes msg from remaining part
            my $message = Jael::Message::unpack($message_string);
        
            Jael::Debug::msg("received : $message (size=" . length($message_string) . ")");
            push @incoming_messages, $message;
        } else {
            return @incoming_messages;
        }
    }
    
    return @incoming_messages;
}

1;
