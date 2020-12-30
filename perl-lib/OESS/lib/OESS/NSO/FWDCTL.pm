package OESS::NSO::FWDCTL;

use AnyEvent;
use Data::Dumper;
use GRNOC::RabbitMQ::Method;
use GRNOC::WebService::Regex;
use HTTP::Request::Common;
use JSON;
use Log::Log4perl;
use LWP::UserAgent;
use XML::LibXML;

use OESS::Config;
use OESS::DB;
use OESS::DB::Node;
use OESS::L2Circuit;
use OESS::Node;
use OESS::NSO::Client;
use OESS::RabbitMQ::Dispatcher;
use OESS::VRF;

use constant FWDCTL_WAITING     => 2;
use constant FWDCTL_SUCCESS     => 1;
use constant FWDCTL_FAILURE     => 0;
use constant FWDCTL_UNKNOWN     => 3;
use constant FWDCTL_BLOCKED     => 4;

=head1 OESS::NSO::FWDCTL

=cut

=head2 new

=cut
sub new {
    my $class = shift;
    my $args  = {
        config          => undef,
        config_filename => '/etc/oess/database.xml',
        logger          => Log::Log4perl->get_logger('OESS.NSO.FWDCTL'),
        @_
    };
    my $self = bless $args, $class;

    if (!defined $self->{config}) {
        $self->{config} = new OESS::Config(config_filename => $self->{config_filename});
    }
    $self->{db} = new OESS::DB(config => $self->{config}->filename);
    $self->{nodes} = {};
    $self->{nso} = new OESS::NSO::Client(config => $self->{config});

    # When this process receives sigterm send an event to notify all
    # children to exit cleanly.
    $SIG{TERM} = sub {
        $self->stop;
    };

    return $self;
}

=head2 start

=cut
sub start {
    my $self = shift;

    # Load devices from database
    my $nodes = OESS::DB::Node::fetch_all(db => $self->{db});
    if (!defined $nodes) {
        warn "Couldn't lookup nodes. FWDCTL will not provision on any existing nodes.";
        $self->{logger}->error("Couldn't lookup nodes. Discovery will not provision on any existing nodes.");
    }
    foreach my $node (@$nodes) {
        $self->{nodes}->{$node->{node_id}} = $node;
    }

    # Setup polling subroutines
    $self->{connection_timer} = AnyEvent->timer(
        after    => 5,
        interval => 300,
        cb       => sub { $self->diff(@_); }
    );

    $self->{dispatcher} = new OESS::RabbitMQ::Dispatcher(
        # queue => 'oess-fwdctl',
        # topic => 'oess.fwdctl.rpc'
        queue => 'MPLS-FWDCTL',
        topic => 'MPLS.FWDCTL.RPC'
    );

    my $add_vlan = GRNOC::RabbitMQ::Method->new(
        name => "addVlan",
        async => 1,
        callback => sub { $self->addVlan(@_) },
        description => "addVlan provisions a l2 connection"
    );
    $add_vlan->add_input_parameter(
        name => "circuit_id",
        description => "Id of the l2 connection to add",
        required => 1,
        attern => $GRNOC::WebService::Regex::INTEGER
    );
    $self->{dispatcher}->register_method($add_vlan);

    my $delete_vlan = GRNOC::RabbitMQ::Method->new(
        name => "deleteVlan",
        async => 1,
        callback => sub { $self->deleteVlan(@_) },
        description => "deleteVlan removes a l2 connection"
    );
    $delete_vlan->add_input_parameter(
        name => "circuit_id",
        description => "Id of the l2 connection to delete",
        required => 1,
        pattern => $GRNOC::WebService::Regex::INTEGER
    );
    $self->{dispatcher}->register_method($delete_vlan);

    my $modify_vlan = GRNOC::RabbitMQ::Method->new(
        name => "modifyVlan",
        async => 1,
        callback => sub { $self->modifyVlan(@_) },
        description => "modifyVlan modifies an existing l2 connection"
    );
    $modify_vlan->add_input_parameter(
        name => "circuit_id",
        description => "Id of l2 connection to be modified.",
        required => 1,
        pattern => $GRNOC::WebService::Regex::INTEGER
    );
    $modify_vlan->add_input_parameter(
        name => "previous",
        description => "Previous version of the modified l2 connection.",
        required => 1,
        pattern => $GRNOC::WebService::Regex::TEXT
    );
    $modify_vlan->add_input_parameter(
        name => "pending",
        description => "Pending version of the modified l2 connection.",
        required => 1,
        pattern => $GRNOC::WebService::Regex::TEXT
    );
    $self->{dispatcher}->register_method($modify_vlan);

    my $add_vrf = GRNOC::RabbitMQ::Method->new(
        name => "addVrf",
        async => 1,
        callback => sub { $self->addVrf(@_) },
        description => "addVrf provisions a l3 connection"
    );
    $self->{dispatcher}->register_method($add_vrf);

    my $delete_vrf = GRNOC::RabbitMQ::Method->new(
        name => "delVrf",
        async => 1,
        callback => sub { $self->delVrf(@_) },
        description => "delVrf removes a l3 connection"
    );
    $self->{dispatcher}->register_method($delete_vrf);

    my $modify_vrf = GRNOC::RabbitMQ::Method->new(
        name => "modifyVrf",
        async => 1,
        callback => sub { $self->modifyVrf(@_) },
        description => "modifyVrf modifies an existing l3 connection"
    );
    $self->{dispatcher}->register_method($modify_vrf);

    # NOTE It's not expected that any children processes will exist in this
    # version of FWDCTL. Result is hardcoded.
    my $check_child_status = GRNOC::RabbitMQ::Method->new(
        name        => "check_child_status",
        description => "check_child_status returns an event id which will return the final status of all children",
        callback    => sub {
            my $method = shift;
            return { status => 1, event_id => 1 };
        }
    );
    $self->{dispatcher}->register_method($check_child_status);

    # NOTE It's not expected that any children processes will exist in this
    # version of FWDCTL. Result is hardcoded.
    my $get_event_status = GRNOC::RabbitMQ::Method->new(
        name        => "get_event_status",
        description => "get_event_status returns the current status of the event",
        callback    => sub {
            my $method = shift;
            return { status => 1 };
        }
    );
    $get_event_status->add_input_parameter(
        name => "event_id",
        description => "the event id to fetch the current state of",
        required => 1,
        pattern => $GRNOC::WebService::Regex::NAME_ID
    );
    $self->{dispatcher}->register_method($get_event_status);

    # TODO It's not clear if both is_online and echo are required; Please
    # investigate.
    my $echo = GRNOC::RabbitMQ::Method->new(
        name        => "echo",
        description => "echo always returns 1",
        callback    => sub {
            my $method = shift;
            return { status => 1 };
        }
    );
    $self->{dispatcher}->register_method($echo);

    my $get_diff_text = GRNOC::RabbitMQ::Method->new(
        name => 'get_diff_text',
        async => 1,
        callback => sub { $self->get_diff_text(@_); },
        description => "Returns a human readable diff for node_id"
    );
    $get_diff_text->add_input_parameter(
        name => "node_id",
        description => "The node ID to lookup",
        required => 1,
        pattern => $GRNOC::WebService::Regex::INTEGER
    );
    $self->{dispatcher}->register_method($get_diff_text);

    # TODO It's not clear if both is_online and echo are required; Please
    # investigate.
    my $is_online = new GRNOC::RabbitMQ::Method(
        name        => "is_online",
        description => 'is_online returns 1 if this service is available',
        async       => 1,
        callback    => sub {
            my $method = shift;
            return $method->{success_callback}({ successful => 1 });
        }
    );
    $self->{dispatcher}->register_method($is_online);

    my $new_switch = new GRNOC::RabbitMQ::Method(
        name        => 'new_switch',
        description => 'new_switch adds a new switch to FWDCTL',
        async       => 1,
        callback    => sub { $self->new_switch(@_); }
    );
    $new_switch->add_input_parameter(
        name        => 'node_id',
        description => 'Id of the new node',
        required    => 1,
        pattern     => $GRNOC::WebService::Regex::NUMBER_ID
    );
    $self->{dispatcher}->register_method($new_switch);

    my $update_cache = GRNOC::RabbitMQ::Method->new(
        name => 'update_cache',
        async => 1,
        callback => sub { $self->update_cache(@_) },
        description => "Rewrites the connection cache file"
    );
    $self->{dispatcher}->register_method($update_cache);

    $self->{dispatcher}->start_consuming;
    return 1;
}

=head2 stop

=cut
sub stop {
    my $self = shift;
    $self->{logger}->info('Stopping OESS::NSO::FWDCTL.');
    $self->{dispatcher}->stop_consuming;
}

=head2 addVlan

=cut
sub addVlan {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    my $conn = new OESS::L2Circuit(
        db => $self->{db},
        circuit_id => $params->{circuit_id}{value}
    );
    $conn->load_endpoints;

    my $err = $self->{nso}->create_l2connection($conn);
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }
    return &$success({ status => FWDCTL_SUCCESS });
}

=head2 deleteVlan

=cut
sub deleteVlan {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    my $err = $self->{nso}->delete_l2connection($params->{circuit_id}{value});
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }
    return &$success({ status => FWDCTL_SUCCESS });
}

=head2 modifyVlan

=cut
sub modifyVlan {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    my $pending_hash = decode($params->{pending}{value});
    my $pending_conn = new OESS::L2Circuit(db => $self->{db}, model => $pending_hash);

    my $err = $self->{nso}->edit_l2connection($pending_conn);
    if (defined $err) {
        $self->{logger}->error($err);
        return &$error($err);
    }

    return &$success({ status => 1 });
}

=head2 addVrf

=cut
sub addVrf {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    return &$success({ status => 1 });
}

=head2 deleteVrf

=cut
sub deleteVrf {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    return &$success({ status => 1 });
}

=head2 modifyVrf

=cut
sub modifyVrf {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    return &$success({ status => 1 });
}

=head2 diff

diff reads all connections from cache, loads all connections from nso,
determines if a configuration change within nso is required, and if so, make
the change.

=cut
sub diff {
    my $self = shift;

    return 1;
}

=head2 get_diff_text

=cut
sub get_diff_text {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    return &$success({ status => 1 });
}

=head2 new_switch

=cut
sub new_switch {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    if (defined $self->{nodes}->{$params->{node_id}{value}}) {
        $self->{logger}->warn("Node $params->{node_id}{value} already registered with FWDCTL.");
        return &$success({ status => 1 });
    }

    my $node = OESS::DB::Node::fetch(db => $self->{db}, node_id => $params->{node_id}{value});
    if (!defined $node) {
        my $err = "Couldn't lookup node $params->{node_id}{value}. FWDCTL will not properly provision on this node.";
        $self->{logger}->error($err);
        &$error($err);
    }
    $self->{nodes}->{$params->{node_id}{value}} = $node;

    warn "Switch $node->{name} registered with FWDCTL.";
    $self->{logger}->info("Switch $node->{name} registered with FWDCTL.");

    # Make first invocation of polling subroutines
    $self->diff;

    return &$success({ status => 1 });
}

=head2 update_cache

=cut
sub update_cache {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{success_callback};
    my $error = $method->{error_callback};

    return &$success({ status => 1 });
}

1;
