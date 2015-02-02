package Jael::ServerEngine;
# vim: autoindent tabstop=4 shiftwidth=4 expandtab softtabstop=4 filetype=perl
use strict;
use warnings;
use threads;
use threads::shared;
use IO::Socket;
use IO::Select;
# auto-flush on socket
$| = 1;
use Jael::Protocol;
use Jael::Message;
use Jael::MessageBuffers;
use Jael::Debug;

# Port par défaut du serveur
use constant PORT => 2345;

# Priorités des threads
use constant {
    SENDING_PRIORITY_LOW => 0,
    SENDING_PRIORITY_HIGH => 1
};

my $max_buffer_reading_size = 1024;

# Crée un nouveau serveur
# Paramètres: ID, [machine 1, machine 2, ...]

# Exemple:
# 1, [m1, m2, m3, m2]
#      0   1   2   3
# 1 est ici est des deux serveurs (donc processus) sur la machine 2
sub new {
    my $class = shift;
    my $self = {};

    bless $self, $class;
 
    # Partage entre les threads
    # Sockets non partagés et gérés par les threads
    my @sh_messages_low :shared;
    my @sh_messages_high :shared;

    # Attributs principaux
    $self->{id} = shift;
    
    my @machines_names :shared = @_;
    
    $self->{machines_names} = \@machines_names;
    $self->{machines_number} = @{$self->{machines_names}};
    
    # Tableau de messages
    $self->{sending_messages} = [];
    $self->{sending_messages}->[SENDING_PRIORITY_LOW] = \@sh_messages_low;
    $self->{sending_messages}->[SENDING_PRIORITY_HIGH] = \@sh_messages_high;
  
    # Buffer du serveur
    $self->{message_buffers} = new Jael::MessageBuffers;

    # Mise en place du protocole à utiliser
    $self->{protocol} = new Jael::Protocol($self);
    
    # Threads pour la gestion de l'envoi de messages
    threads->create(\&th_send_with_priority, $self->{id}, $self->{machines_names}->[$self->{id}], 
                    \@sh_messages_low, \@machines_names, SENDING_PRIORITY_LOW);  
    threads->create(\&th_send_with_priority, $self->{id}, $self->{machines_names}->[$self->{id}], 
                    \@sh_messages_high, \@machines_names, SENDING_PRIORITY_HIGH); 

    # Informations de debug
    Jael::Debug::init($self->{id}, $self->{machines_names}->[$self->{id}]);

    return $self;
}

# Affichage des informations concernant un serveur
sub print_infos {
    my $self = shift;

    print "# Server\n";
    print "Server Id: " . $self->{id} . "\n";
    print "Server Name: " . $self->{machines_names}->[$self->{id}] . "\n";
    print "Machines number: " . $self->{machines_number} . "\n";
    print "Machines: " . join(", ", @{$self->{machines_names}}) . "\n\n";
}

sub run {
    my $self = shift;
    Jael::Debug::msg('starting new server');

    $self->print_infos();

    # server port is PORT + id of current server
    $self->{server_socket} = IO::Socket::INET->new(LocalHost => $self->{machines_names}->[$self->{id}], Listen => 1, LocalPort => PORT + $self->{id}, Reuse => 1, Proto => 'tcp');
    die "Could not create socket: $!\n" unless $self->{server_socket};

    # we use select to find non blocking reads
    $self->{read_set} = IO::Select->new( $self->{server_socket} );

    while(my @ready = $self->{read_set}->can_read()) {
        for my $fh (@ready) {
            if($fh == $self->{server_socket}) {
                Jael::Debug::msg("new connexion");
                # Create a new socket
                my $new = $self->{server_socket}->accept;
                $self->{read_set}->add($new);
            }
            else {
                my $buffer;
                my $size = $max_buffer_reading_size;
                $fh->recv($buffer, $size);
                if ($size == 0) {
                    Jael::Debug::msg("connection closed");
                    $self->{read_set}->remove($fh);
                    close($fh);
                } else {
                    $self->{message_buffers}->incoming_data($fh, $buffer);
                }
            }
        }
    }
    return;
}

#broadcast to everyone but self
#slow and dumb broadcast with a loop
sub broadcast {
    my $self = shift;
    my $message = shift;
    Jael::Debug::msg("broadcasting $message");
    for my $machine_id (0..$#{$self->{machines_names}}) {
        next if $machine_id == $self->{id};
        $self->send($machine_id, $message);
    }
}

# Thread se chargeant d'envoyer des messages avec une certaine priorité
# Paramètres : Hashtable de sockets, Tableau de id + messages
sub th_send_with_priority {
    my $id = shift;           # ID de la machine courante
    my $machine_name = shift; # Nom de la machine courante
    
    my $sending_sockets = {};     # Liste des sockets connues sur le réseau
    my $sending_messages = shift; # Liste de messages à envoyer
    my $machines_names = shift;   # Liste des machines 
    my $priority = shift;         # Priorité du thread
    
    my $string;            # Chaine à envoyer
    my $target_machine_id; # ID de la machine cible

    Jael::Debug::init($id, $machine_name);

    while (1) {
        {
            sleep(0.1);
            Jael::Debug::msg("th (priority=$priority): sleep");
            lock($sending_messages);                                 
            cond_wait($sending_messages) unless @{$sending_messages}; # On attend si rien dans le tableau
            Jael::Debug::msg("th (priority=$priority): waken");
            $target_machine_id = shift @{$sending_messages};          # Machine cible
            $string = shift @{$sending_messages};                     # Message pour la machine de destination
        }
                    
        # On se connecte si aucun socket n'existe pour un groupe de priorité donné
        connect_to($machines_names, $target_machine_id, $sending_sockets) unless exists $sending_sockets->{$target_machine_id};

        # Récupération socket
        my $socket = $sending_sockets->{$target_machine_id};
        Jael::Debug::msg("sending message (priority=$priority)");

        # Envoi du message
        print $socket $string;    
    }
}

# Envoyer un message sur une machine
# Paramètres: Machine cible, message
sub send {
    my $self = shift;
    my $target_machine_id = shift;
    my $message = shift;

    # ID de la machine source (donc le serveur courant) à mettre dans le message
    $message->set_sender_id($self->{id});

    # Choix de la priorité
    # TMP
    my $priority = $message->get_type == TASK_COMPUTATION_COMPLETED ? SENDING_PRIORITY_LOW : SENDING_PRIORITY_HIGH;

    # Ajout du message dans la bonne liste de messages en fonction de la priorité
    {
        lock($self->{sending_messages}->[$priority]);
        push @{$self->{sending_messages}->[$priority]}, ($target_machine_id, $message->pack());

        Jael::Debug::msg("new message in queue (id_dest=$target_machine_id, priority=$priority)");
        cond_signal($self->{sending_messages}->[$priority]);
    }
}

# Ajouter une connexion d'un client au serveur
# Paramètres : ID de la machine cliente, liste de sockets
sub connect_to {
    my $machines_names = shift;
    my $machine_id = shift;
    my $sending_sockets = shift;

    my $port = PORT + $machine_id;
    my $machine = $machines_names->[$machine_id];

    while (not defined $sending_sockets->{$machine_id}) {
        Jael::Debug::msg("connect_to (machine_addr=$machine, port=$port)");

        $sending_sockets->{$machine_id} = IO::Socket::INET->new(
            PeerAddr => $machine,
            PeerPort => $port,
            Proto => 'tcp'
            );

        sleep(0.1);
    }
    
    Jael::Debug::msg("opened connection to $machine_id");
}

1;
