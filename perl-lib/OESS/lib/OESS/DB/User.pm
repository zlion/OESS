#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::User;

sub fetch{
    my %params = @_;
    my $db = $params{'db'};
    my $user_id = $params{'user_id'};

    my $user = $db->execute_query("select * from user where user_id = ?",[$user_id]);
    
    if(!defined($user) || !defined($user->[0])){
        return;
    }

    return $user->[0];

}

sub find_user_by_remote_auth{
    my %params = @_;
    my $db = $params{'db'};
    my $remote_user = $params{'remote_user'};

    my $user_id = $db->execute_query("select remote_auth.user_id from remote_auth where remote_auth.auth_name = ?",[$remote_user]);
    if(!defined($user_id) || !defined($user_id->[0])){
        return;
    }

    return $user_id->[0];
}

1;
