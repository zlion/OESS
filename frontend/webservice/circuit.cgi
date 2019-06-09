#!/usr/bin/perl -I /home/aragusa/OESS/perl-lib/OESS/lib

use strict;
use warnings;

use Data::Dumper;
use DateTime;
use Digest::MD5 qw(md5_hex);
use JSON;
use Log::Log4perl;

use GRNOC::WebService::Dispatcher;
use GRNOC::WebService::Method;

use OESS::Cloud;
use OESS::DB;
use OESS::DB::Circuit;
use OESS::DB::Entity;
use OESS::DB::User;
use OESS::Entity;
use OESS::L2Circuit;
use OESS::RabbitMQ::Client;
use OESS::VRF;


Log::Log4perl::init_and_watch('/etc/oess/logging.conf', 10);


my $db = OESS::DB->new();
my $mq = OESS::RabbitMQ::Client->new(
    topic   => 'OF.FWDCTL.RPC',
    timeout => 120
);

my $ws = GRNOC::WebService::Dispatcher->new();

my $get_circuits = GRNOC::WebService::Method->new(
    name => 'get',
    callback => \&get,
    description => 'Returns a list of Circuits filtered by the provided parameters.'
);
$get_circuits->add_input_parameter(
    name => 'workgroup_id',
    pattern => $GRNOC::WebService::Regex::INTEGER,
    required => 1,
    description => 'Identifier of Workgroup to filter results by.'
);
$get_circuits->add_input_parameter(
    name => 'circuit_id',
    pattern => $GRNOC::WebService::Regex::INTEGER,
    required => 0,
    description => 'Identifier of Circuit to filter results by.'
);
$get_circuits->add_input_parameter(
    name => 'state',
    pattern => $GRNOC::WebService::Regex::TEXT,
    default => 'active',
    required => 0,
    description => 'State of Circuits to search for. Must be `active` or `decom`.'
);
$ws->register_method($get_circuits);

sub get {
    my ($method, $args) = @_;

    my $circuits = [];
    my $circuit_datas = OESS::DB::Circuit::fetch_circuits(
        db => $db,
        state => $args->{state}->{value},
        circuit_id => $args->{circuit_id}->{value},
        workgroup_id => $args->{workgroup_id}->{value}
    );

    foreach my $data (@$circuit_datas) {
        my $first_circuit = OESS::DB::Circuit::fetch_circuits(
            db => $db,
            circuit_id => $data->{circuit_id},
            first => 1
        );

        $data->{created_by_id} = $first_circuit->[0]->{user_id} || $data->{user_id};
        $data->{created_on_epoch} = $first_circuit->[0]->{start_epoch} || $data->{start_epoch};
        $data->{created_on} = DateTime->from_epoch(
            epoch => $data->{'created_on_epoch'}
        )->strftime('%m/%d/%Y %H:%M:%S');

        my $obj = new OESS::L2Circuit(db => $db, model => $data);
        $obj->load_workgroup;
        $obj->load_users;
        $obj->load_paths;
        $obj->load_endpoints;

        push @$circuits, $obj->to_hash;
    }

    return {results => $circuits};
}


my $provision = GRNOC::WebService::Method->new(
    name        => 'provision',
    callback    => \&provision,
    description => 'Creates and provisions a new Circuit.'
);
$provision->add_input_parameter(
    name        => 'circuit_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    description => "-1 or undefined indicate circuit is to be added."
);
$provision->add_input_parameter(
    name        => 'workgroup_id',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => 'Identifier of managing Workgroup.'
);

$provision->add_input_parameter(
    name        => 'description',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    description => "The description of the circuit."
);

$provision->add_input_parameter(
	name        => 'provision_time',
	pattern     => $GRNOC::WebService::Regex::INTEGER,
	required    => 1,
	description => "Timestamp of when circuit should be created in epoch time format. -1 means now."
);
$provision->add_input_parameter(
    name        => 'remove_time',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 1,
    description => "The time the circuit should be removed from the network in epoch time format. -1 means never."
);
$provision->add_input_parameter(
    name        => 'skip_cloud_provisioning',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    default     => 0,
    description => "If set to 1 cloud provider configurations will not be performed."
);

$provision->add_input_parameter(
	name        => 'link',
	pattern     => $GRNOC::WebService::Regex::TEXT,
	required    => 0,
	multiple    => 1,
	description => "Array of names of links to be used in the primary path."
);

$provision->add_input_parameter(
    name        => 'endpoint',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 1,
    multiple    => 1,
    description => 'JSON array of endpoints to be used.'
);

$provision->add_input_parameter(
    name        => 'external_identifier',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => "External Identifier of the circuit"
);
$provision->add_input_parameter(
    name        => 'remote_url',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => "The remote URL for the IDC"
);
$provision->add_input_parameter(
    name        => 'remote_requester',
    pattern     => $GRNOC::WebService::Regex::TEXT,
    required    => 0,
    description => "The remote requester."
);
$ws->register_method($provision);

sub provision {
    my ($method, $args) = @_;

    my $user = OESS::DB::User::fetch(db => $db, username => $ENV{REMOTE_USER});
    if (!defined $user) {
        $method->set_error("User '$user->{auth_name}' is invalid.");
        return;
    }
    if ($user->{type} eq 'read-only') {
        $method->set_error("User '$user->{auth_name}' is read-only.");
        return;
    }

    if (defined $args->{circuit_id}->{value} && $args->{circuit_id}->{value} != -1) {
        return update($method, $args);
    }

    $db->start_transaction;

    my $circuit = new OESS::L2Circuit(
        db => $db,
        model => {
            name => $args->{description}->{value},
            description => $args->{description}->{value},
            remote_url => $args->{remote_url}->{value},
            remote_requester => $args->{remote_requester}->{value},
            external_identifier => $args->{external_identifier}->{value},
            provision_time => $args->{provision_time}->{value},
            remove_time => $args->{remove_time}->{value},
            user_id => $user->{user_id},
            workgroup_id => $args->{workgroup_id}->{value}
        }
    );

    my ($circuit_id, $circuit_error) = $circuit->create;
    if (defined $circuit_error) {
        $method->set_error("Couldn't create Circuit: $circuit_error");
        $db->rollback;
        return;
    }

    if (@{$args->{endpoint}->{value}} < 2) {
        $method->set_error("Couldn't create Circuit: Circuit requires at least two Endpoints.");
        $db->rollback;
        return;
    }

    # Endpoint: { entity: 'entity name', bandwidth: 0, tag: 100, inner_tag: 100, peerings: [{ version: 4 }]  }
    foreach my $value (@{$args->{endpoint}->{value}}) {
        my $ep;
        eval{
            $ep = decode_json($value);
        };
        if ($@) {
            $method->set_error("Cannot decode endpoint: $@");
            return;
        }

        my $entity = new OESS::Entity(db => $db, name => $ep->{entity});

        my $interface = $entity->select_interface(
            inner_tag    => $ep->{inner_tag},
            tag          => $ep->{tag},
            workgroup_id => $args->{workgroup_id}->{value}
        );
        if (!defined $interface) {
            $method->set_error("Couldn't create Circuit: Cannot find a valid Interface for $ep->{entity}.");
            $db->rollback;
            return;
        }

        my $valid_bandwidth = $interface->is_bandwidth_valid(bandwidth => $ep->{bandwidth});
        if (!$valid_bandwidth) {
            $method->set_error("Couldn't create Circuit: The specified bandwidth is invalid for $ep->{entity}.");
            $db->rollback;
            return;
        }

        # Populate Endpoint modal with selected Interface details.
        $ep->{entity_id}    = $entity->{entity_id};
        $ep->{interface}    = $interface->{name};
        $ep->{interface_id} = $interface->{interface_id};
        $ep->{node}         = $interface->{node}->{name};
        $ep->{node_id}      = $interface->{node}->{node_id};
        $ep->{cloud_interconnect_id}   = $interface->cloud_interconnect_id;
        $ep->{cloud_interconnect_type} = $interface->cloud_interconnect_type;

        my $endpoint = new OESS::Endpoint(db => $db, model => $ep);
        $circuit->add_endpoint($endpoint);

        if ($interface->cloud_interconnect_type eq 'azure-express-route') {
            my $interface2 = $entity->select_interface(
                inner_tag    => $endpoint->{inner_tag},
                tag          => $endpoint->{tag},
                workgroup_id => $args->{workgroup_id}->{value}
            );
            if (!defined $interface2) {
                $method->set_error("Cannot find a valid Interface for $endpoint->{entity}.");
                $db->rollback;
                return;
            }

            # Populate Endpoint modal with selected Interface details.
            $ep->{entity_id}    = $entity->{entity_id};
            $ep->{interface}    = $interface2->{name};
            $ep->{interface_id} = $interface2->{interface_id};
            $ep->{node}         = $interface2->{node}->{name};
            $ep->{node_id}      = $interface2->{node}->{node_id};
            $ep->{cloud_interconnect_id}   = $interface2->cloud_interconnect_id;
            $ep->{cloud_interconnect_type} = $interface2->cloud_interconnect_type;

            my $endpoint2 = new OESS::Endpoint(db => $db, model => $ep);
            $circuit->add_endpoint($endpoint2);
        }
    }

    if (!$args->{skip_cloud_provisioning}->{value}) {
        eval {
            $circuit->{endpoints} = OESS::Cloud::setup_endpoints($circuit->name, $circuit->endpoints);
        };
        if ($@) {
            $method->set_error("Couldn't create Circuit: $@");
            $db->rollback;
            return;
        }
    }

    foreach my $ep (@{$circuit->endpoints}) {
        my ($ep_id, $ep_err) = $ep->create(
            circuit_id => $circuit_id,
            workgroup_id => $args->{workgroup_id}->{value}
        );
        if (defined $ep_err) {
            $method->set_error("Couldn't create Circuit: $ep_err");
            $db->rollback;
            return;
        }
    }

    if (defined $args->{link}->{value}) {
        if (@{$circuit->endpoints} > 2) {
            $method->set_error("Couldn't create Circuit: Static path are unsupported on Circuits with more than two Endpoints.");
            $db->rollback;
            return;
        }

        my $path = new OESS::Path(
            db => $db,
            model => {
                mpls_type  => 'strict',
                state      => 'active',
                type       => 'primary'
            }
        );

        foreach my $value (@{$args->{link}->{value}}) {
            my $link = new OESS::Link(db => $db, name => $value);
            if (!defined $link) {
                $method->set_error("Couldn't create Circuit: Unknown link $value used in static Path.");
                $db->rollback;
                return;
            }
            $path->add_link($link);
        }

        my $eps = $circuit->endpoints;
        my $node_a = $eps->[0]->node_id;
        my $node_z = $eps->[1]->node_id;

        my $ok = $path->connects($node_a, $node_z);
        if (!$ok) {
            $method->set_error("Couldn't create Circuit: Static Path doesn't connect selected Endpoints.");
            $db->rollback;
            return;
        }

        my ($path_id, $path_err) = $path->create(circuit_id => $circuit_id);
        if (defined $path_err) {
            $method->set_error("Couldn't create Circuit: $path_err");
            $db->rollback;
            return;
        }

        $circuit->add_path($path);
    }

    # Put rollback in place for quick tests
    # $db->rollback;
    $db->commit;

    warn Dumper($circuit->to_hash);
    return {success => 1, circuit_id => $circuit_id};
}


sub update {
    my ($method, $args) = @_;

    $db->start_transaction;

    my $circuit = new OESS::L2Circuit(
        db => $db,
        circuit_id => $args->{circuit_id}->{value}
    );
    if (!defined $circuit) {
        $method->set_error("Couldn't load Circuit from database.");
        return;
    }

    $circuit->load_endpoints;
    $circuit->load_paths;

    $circuit->description($args->{description}->{value});
    $circuit->remote_url($args->{remote_url}->{value});
    $circuit->remote_requester($args->{remote_requester}->{value});
    $circuit->external_identifier($args->{external_identifier}->{value});

    my $err = $circuit->update;
    if (defined $err) {
        $method->set_error("Couldn't update Circuit: $err");
        return;
    }

    # Hash to track which endpoints have been updated and which shall
    # be removed.
    my $endpoints = {};
    foreach my $ep (@{$circuit->endpoints}) {
        $endpoints->{$ep->circuit_ep_id} = $ep;
    }

    foreach my $value (@{$args->{endpoint}->{value}}) {
        my $ep;
        eval{
            $ep = decode_json($value);
        };
        if ($@) {
            $method->set_error("Cannot decode endpoint: $@");
            return;
        }

        if (!defined $ep->{circuit_ep_id}) {
            warn "Adding Endpoint";

            my $entity = new OESS::Entity(db => $db, name => $ep->{entity});

            my $interface = $entity->select_interface(
                inner_tag    => $ep->{inner_tag},
                tag          => $ep->{tag},
                workgroup_id => $args->{workgroup_id}->{value}
            );
            if (!defined $interface) {
                $method->set_error("Cannot find a valid Interface for $ep->{entity}.");
                return;
            }

            $ep->{entity_id}    = $entity->{entity_id};
            $ep->{interface}    = $interface->{name};
            $ep->{interface_id} = $interface->{interface_id};
            $ep->{node}         = $interface->{node}->{name};
            $ep->{node_id}      = $interface->{node}->{node_id};

            my $endpoint = new OESS::Endpoint(db => $db, model => $ep);
            $endpoint->create(
                circuit_id => $circuit->circuit_id,
                workgroup_id => $args->{workgroup_id}->{value}
            );
            $circuit->add_endpoint($endpoint);

        } else {
            my $endpoint = $circuit->get_endpoint(
                circuit_ep_id => $ep->{circuit_ep_id}
            );

            $endpoint->bandwidth($ep->{bandwidth});
            $endpoint->inner_tag($ep->{inner_tag});
            $endpoint->tag($ep->{tag});
            $endpoint->mtu($ep->{mtu});
            my $err = $endpoint->update_db;
            if (defined $err) {
                $method->set_error("Couldn't update Endpoint: $err");
                return;
            }

            delete $endpoints->{$endpoint->circuit_ep_id};
        }
    }

    foreach my $key (keys %$endpoints) {
        my $endpoint = $endpoints->{$key};
        $endpoint->remove;
        $circuit->remove_endpoint($endpoint->{circuit_ep_id});
    }

    # Hash to track which links have been updated and which shall be
    # removed from the primary / strict path.
    my $links = {};

    # TODO handle case when static path is added to an existing
    # circuit
    my $path  = $circuit->get_path(path => 'primary');
    if (defined $path) {
        foreach my $link (@{$path->links}) {
            $links->{$link->name} = $link;
        }

        foreach my $value (@{$args->{link}->{value}}) {
            if (!defined $links->{$value}) {
                # New
            } else {
                # Update / Ignore
                delete $links->{$value};
            }
        }

        foreach my $key (keys %$links) {
            $path->remove_link(name => $key);
        }
    }

    # Put rollback in place for quick tests
    # $db->rollback;
    $db->commit;

    warn Dumper($circuit->to_hash);
    return { success => 1, circuit_id => $circuit->circuit_id };
}


my $remove = GRNOC::WebService::Method->new(
    name => 'remove',
    callback => \&remove,
    description => 'Removes a Circuit from the network.'
);
$remove->add_input_parameter(
    name => 'workgroup_id',
    pattern => $GRNOC::WebService::Regex::INTEGER,
    required => 1,
    description => 'Identifier of managing Workgroup.'
);
$remove->add_input_parameter(
    name => 'circuit_id',
    pattern => $GRNOC::WebService::Regex::INTEGER,
    required => 1,
    description => 'Identifier of Circuit to remove.'
);
$remove->add_input_parameter(
    name        => 'skip_cloud_provisioning',
    pattern     => $GRNOC::WebService::Regex::INTEGER,
    required    => 0,
    default     => 0,
    description => "If set to 1 cloud provider configurations will not be performed."
);
$ws->register_method($remove);

sub remove {
    my ($method, $args) = @_;

    my $user = OESS::DB::User::fetch(db => $db, username => $ENV{REMOTE_USER});
    if (!defined $user) {
        $method->set_error("User '$user->{auth_name}' is invalid.");
        return;
    }
    if ($user->{type} eq 'read-only') {
        $method->set_error("User '$user->{auth_name}' is read-only.");
        return;
    }

    $db->start_transaction;

    my $circuit = new OESS::L2Circuit(
        db => $db,
        circuit_id => $args->{circuit_id}->{value}
    );
    if (!defined $circuit) {
        $method->set_error("Couldn't load Circuit from database.");
        $db->rollback;
        return;
    }

    $circuit->load_endpoints;
    $circuit->load_paths;

    if (!$args->{skip_cloud_provisioning}->{value}) {
        eval {
            $circuit->{endpoints} = OESS::Cloud::cleanup_endpoints($circuit->name, $circuit->endpoints);
        };
        if ($@) {
            $method->set_error("Couldn't remove Circuit: $@");
            $db->rollback;
            return;
        }
    }

    foreach my $ep (@{$circuit->endpoints}) {
        my $err = $ep->remove;
        if (defined $err) {
            $method->set_error("Couldn't remove Circuit: $err");
            $db->rollback;
            return;
        }
    }

    foreach my $path (@{$circuit->paths}) {
        my $err = $path->remove;
        if (defined $err) {
            $method->set_error("Couldn't remove Circuit: $err");
            $db->rollback;
            return;
        }
    }

    my $err = $circuit->remove(user_id => $user->{user_id});
    if (defined $err) {
        $method->set_error("Couldn't remove Circuit: $err");
        $db->rollback;
        return;
    }

    # Put rollback in place for quick tests
    # $db->rollback;
    $db->commit;

    return {status => 1};
}


$ws->handle_request();
