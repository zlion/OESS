#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::VRF;

use OESS::Endpoint;
use OESS::Peer;
use OESS::Interface;
use OESS::User;
use OESS::Workgroup;

use Data::Dumper;


sub fetch{
    my %params = @_;
    my $db = $params{'db'};
    
    my $status = $params{'status'} || 'active';

    my $vrf_id = $params{'vrf_id'};

    my $details;

    my $res = $db->execute_query("select * from vrf where vrf_id = ?", [$vrf_id]);
    if(!defined($res) || !defined($res->[0])){
        return;
    }

    $details = $res->[0];
    
    my $created_by = OESS::User->new( db => $db, user_id => $details->{'created_by'});
    my $last_modified_by = OESS::User->new(db => $db, user_id => $details->{'last_modified_by'});
    my $workgroup = OESS::Workgroup->new( db => $db, workgroup_id => $details->{'workgroup_id'});

    $details->{'last_modified_by'} = $last_modified_by;
    $details->{'created_by'} = $created_by;
    $details->{'workgroup'} = $workgroup;
   

    my $ep_ids = OESS::DB::VRF::fetch_endpoints(db => $db, vrf_id => $vrf_id);
    
    foreach my $ep (@$ep_ids){
        push(@{$details->{'endpoints'}}, OESS::Endpoint->new(db => $db, type => 'vrf', vrf_endpoint_id => $ep->{'vrf_ep_id'}));
    }
    
    return $details;
}

sub update{
    my %params = @_;
    
    if(!defined($params{'vrf_id'}) || $params{'vrf_id'} == -1){
        return _create_vrf(\%params);
    }else{
        return _update_vrf(\%params);
    }
    
}

sub create{
    my %params = @_;
    my $db = $params{'db'};
    my $model = $params{'model'};
    
    $db->start_transaction();
 
   
    my $vrf_id = $db->execute_query("insert into vrf (name, description, workgroup_id, created, created_by, last_modified, last_modified_by, state) VALUES (?,?,?,unix_timestamp(now()), ?, unix_timestamp(now()), ?, 'active')", [$model->{'name'}, $model->{'description'},$model->{'workgroup'}->{'workgroup_id'}, $model->{'created_by'}->{'user_id'}, $model->{'last_modified_by'}->{'user_id'}]);
    if(!defined($vrf_id)){
        my $error = $db->get_error();
        $db->rollback();
        return;
    }
    
    foreach my $ep (@{$model->{'endpoints'}}){
        my $res = OESS::DB::VRF::add_endpoint(db => $db, model => $ep, vrf_id => $vrf_id);
        if(!defined($res)){
            $db->rollback();
            return;
        }
    }
    
    $db->commit();

    return $vrf_id;
}        

sub delete_endpoint{
    my %params = @_;

    
    
} 

sub add_endpoint{       
    my %params = @_;

    my $db = $params{'db'};
    my $model = $params{'model'};
    my $vrf_id = $params{'vrf_id'};

    my $vrf_ep_id = $db->execute_query("insert into vrf_ep (interface_id, tag, bandwidth, vrf_id, state) VALUES (?,?,?,?,?)",[$model->{'interface'}->{'interface_id'}, $model->{'tag'}, $model->{'bandwidth'}, $vrf_id, 'active']);
    if(!defined($vrf_ep_id)){
        my $error = $db->get_error();
        $db->rollback();
        return;
    }
 
    foreach my $peer (@{$model->{'peers'}}){
        my $res = add_peer(db => $db, model => $peer, vrf_ep_id => $vrf_ep_id);
        if(!defined($res)){
            my $error = $db->get_error();
            $db->rollback();
            return;
        }
    }

    return $vrf_ep_id;
}

sub add_peer{
    my %params = @_;
    
    my $db = $params{'db'};
    my $model = $params{'model'};
    my $vrf_ep_id = $params{'vrf_ep_id'};
    warn "PEER MODEL: " . Dumper($model);

    my $res = $db->execute_query("insert into vrf_ep_peer (vrf_ep_id, peer_ip, local_ip, peer_asn, md5_key, state) VALUES (?,?,?,?,?,?)",[$vrf_ep_id, $model->{'peer_ip'}, $model->{'local_ip'}, $model->{'peer_asn'}, $model->{'key'}, 'active']);

    if(!defined($res)){
        my $error = $db->get_error();
        return;
    }

    return $res;
}

sub fetch_endpoints{
    my %params = @_;

    my $db = $params{'db'};
    my $vrf_id = $params{'vrf_id'};
    my $status = $params{'status'} || 'active';

    #find endpoints 
    my $res = $db->execute_query("select vrf_ep.vrf_ep_id from vrf_ep where vrf_id = ? and state = ?", [$vrf_id, $status]);
    if(!defined($res) || !defined($res->[0])){
        return;
    }

    return $res;

}

sub fetch_endpoint{
    my %params = @_;

    my $db = $params{'db'};
    my $vrf_ep_id = $params{'vrf_endpoint_id'};
    my $status = $params{'status'} || 'active';

    my $vrf_ep = $db->execute_query("select * from vrf_ep where vrf_ep_id = ?", [$vrf_ep_id]);
    
    if(!defined($vrf_ep) || !defined($vrf_ep->[0])){
        return;
    }

    $vrf_ep = $vrf_ep->[0];

    my $interface = OESS::Interface->new(db => $db, interface_id => $vrf_ep->{'interface_id'});
    my $peers = OESS::DB::VRF::fetch_endpoint_peers(db => $db, vrf_ep_id => $vrf_ep_id);

    my @peers;
    foreach my $peer (@$peers){
        push(@peers, OESS::Peer->new( vrf_ep_peer_id => $peer->{'vrf_ep_peer_id'}, db => $db));
    }

    $vrf_ep->{'peers'} = \@peers;
    $vrf_ep->{'interface'} = $interface;

    return $vrf_ep;    
}


sub fetch_endpoint_peers{
    my %params = @_;
    
    my $db = $params{'db'};
    my $vrf_ep_id = $params{'vrf_ep_id'};
    my $status = 'active';

    my $bgp_res = $db->execute_query("select vrf_ep_peer_id from vrf_ep_peer where vrf_ep_id = ? and state = ?",[$vrf_ep_id, $status]);
    
    return $bgp_res;
     
}

sub fetch_peer{
    my %params = @_;
    
    my $db = $params{'db'};
    my $vrf_ep_peer_id = $params{'vrf_ep_peer_id'};

    my $peer = $db->execute_query("select * from vrf_ep_peer where vrf_ep_peer_id = ?",[$vrf_ep_peer_id]);

    if(!defined($peer) || !defined($peer->[0])){
        return;
    }

    $peer = $peer->[0];
    return $peer;


}

sub _update_vrf{
        
        
}

sub get_vrfs{
    my %params = @_;
    my $db = $params{'db'};

    my $where;
    my @where;

    if(defined($params{'state'})){
        push(@where,$params{'state'});
        $where .= " state =";
    }

    my $vrfs = $db->execute_query("select vrf_id from vrf where state = 'active'",[]);
    return $vrfs;
}
    
    1;
