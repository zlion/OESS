#!/bin/bash

function rest_req() {
	args=$@
	echo $#
	echo $@
	command="$command_root\"$command_url/$command_cat?method=$method&$param\""

	echo $command
	eval $command
}

#rest_req "command1" "param1"

command_root="curl -k --user 'lzhang9:Berk\$9718lab@2022' "
#command_root="curl -k --user 'sense-noc:Temppassword01!' "
command_url="https://al2s.net.internet2.edu//oess/services-kerb"


#curl -k --user 'lzhang9:Berk$9718lab@2022' https://al2s.net.internet2.edu//oess/services-kerb/data.cgi

#curl -k --user 'lzhang9:Berk$9718lab@2022' "https://al2s.net.internet2.edu//oess/services-kerb/user.cgi?method=get_current"

#curl -k --user 'lzhang9:Berk$9718lab@2022' "https://al2s.net.internet2.edu//oess/services-kerb/command.cgi?method=get_commands"

#
# data
#
command_cat="data.cgi"

#method="get_all_resources_for_workgroup"
#param="workgroup_id=1504"
#command="$command_root\"$command_url/$command_cat?method=$method&$param\""

#method="get_workgroup_interfaces"
#param="workgroup_id=1504"
#command="$command_root\"$command_url/$command_cat?method=$method&$param\""

#method="get_workgroup_members"
#param="workgroup_id=1504"
#command="$command_root \"$command_url/$command_cat?method=$method&$param\""

#method="get_maps"
#param="workgroup_id=1504"
#command="$command_root \"$command_url/$command_cat?method=$method&$param\""

#method="get_workgroups"
#command="$command_root \"$command_url/$command_cat?method=$method\""

#method="get_node_interfaces"
#param="node=core2.chic.net.internet2.edu"
#param2="workgroup_id=281"
#command="$command_root\"$command_url/$command_cat?method=$method&$param&$param2\""

#method="get_interface"
#param="interface_id=124214"
#command="$command_root \"$command_url/$command_cat?method=$method&$param\""

# INVALIDE: return NULL
#method="get_vlan_tag_range"
#param="interface=HundredGigE0/0/0/24"
#param1="node=core2.sunn.net.internet2.edu"
#param2="workgroup_id=1504"
#command="$command_root \"$command_url/$command_cat?method=$method&$param&$param1&$param2\""

#method="get_existing_circuits"
#param="workgroup_id=1504"
#command="$command_root \"$command_url/$command_cat?method=$method&$param\""

## NOT supported
#method="get_shortest_path"
#param="type=mpls"
#param1="node=core2.chic.net.internet2.edu"
#param2="node=core2.sunn.net.internet2.edu"
#command="$command_root \"$command_url/$command_cat?method=$method&$param&$param1&$param2\""

#"https://al2s.net.internet2.edu//oess/services-kerb/data.cgi?action=get_shortest_path&type=mpls&node=core2.chic.net.internet2.edu&interface=HundredGigE0/0/0/26&tag=821&node=core2.sunn.net.internet2.edu&interface=HundredGigE0/0/0/24&tag=821"
#"https://al2s.net.internet2.edu//oess/services-kerb/provisioning.cgi?action=provision_circuit&circuit_id=-1&description=urn%3Aogf%3Anetwork%3Aal2s.internet2.net%3Aoess%3Al2switching%3Aconn%2B0d898b39-7b00-4409-a45a-c592415cf8a6%3Aresource%2Blinks-chic-sunny%3Avlan%2B821&bandwidth=0&provision_time=-1&remove_time=-1&workgroup_id=1504&node=core2.chic.net.internet2.edu&interface=HundredGigE0/0/0/26&tag=821&node=core2.sunn.net.internet2.edu&interface=HundredGigE0/0/0/24&tag=821"


#
# circuit
#
command_cat="circuit.cgi"

#method="get"
#param="workgroup_id=1504"
#command="$command_root \"$command_url/$command_cat?method=$method&$param\""

#method="remove"
#param="workgroup_id=1504"
#param1="circuit_id=393263"
#command="$command_root \"$command_url/$command_cat?method=$method&$param&$param1\""

# https://www.urlencoder.org
# https://github.com/GlobalNOC/OESS/blob/2.0.15-dev/docs/_api_endpoints/circuit.md
#method="provision"
#param="circuit_id=-1"
#param1="description=sense-circuit"
#param2="provision_time=-1"
#param3="remove_time=-1"
#param4="workgroup_id=1504"
#param5="endpoint=a%7B%22node%22%3A%22core2.chic.net.internet2.edu%22%2C%22bandwidth%22%3A%220%22%2C%22name%22%3A%22sense-connection%22%2C%22description%22%3A%22test_sense%22%2C%22tag%22%3A%222560%22%2C%22interface%22%3A%22HundredGigE0%5C%2F0%5C%2F0%5C%2F26%22%7D"
#command="$command_root \"$command_url/$command_cat?method=$method&$param&$param1&$param2&$param3&$param4&$param5\""

#
# entity
#
command_cat="entity.cgi"

#method="get_entities"
#param="workgroup_id=1504"
#command="$command_root \"$command_url/$command_cat?method=$method&$param\""

#method="get_entity"
#param="workgroup_id=1504"
#command="$command_root \"$command_url/$command_cat?method=$method&$param\""

#method="get_entity_interfaces"
#param="entity_id=3825"
#command="$command_root \"$command_url/$command_cat?method=$method&$param\""

#
# interface
#
command_cat="interface.cgi"

## INVALID: return NULL
#method="get_workgroup_interfaces"
#param="workgroup_id=1504"
#command="$command_root \"$command_url/$command_cat?method=$method&$param\""

#method="get_available_vlans"
#param="interface_id=124214"
#param2="workgroup_id=1504"
#command="$command_root \"$command_url/$command_cat?method=$method&$param&$param2\""

#method="get_interface"
#param="interface_id=124214"
#command="$command_root \"$command_url/$command_cat?method=$method&$param\""

#
# user
#
command_cat="user.cgi"

#method="get_current"
#command="$command_root \"$command_url/$command_cat?method=$method\""

#method="create_user"
#email="email=sense-noc@es.net"
#first_name="first_name=SENSE"
#last_name="last_name=API"
#username="username=sense-noc"
#command="$command_root \"$command_url/$command_cat?method=$method&$email&$first_name&$last_name&$username\""

#
# workgroup_management
#
command_cat="workgroup.cgi"

#method="get_workgroup_users"
#param="workgroup_id=1504"
#command="$command_root \"$command_url/$command_cat?method=$method&$param\""


#
# user
#
command_cat="vrf.cgi"

method="get_vrfs"
param="workgroup_id=1504"
command="$command_root \"$command_url/$command_cat?method=$method&$param\""


#method="provision"
#param="circuit_id=-1"
#param1="description=sense-circuit"
#param2="provision_time=-1"
#param3="remove_time=-1"
#param4="workgroup_id=1504"
#param5="endpoint=a%7B%22node%22%3A%22core2.chic.net.internet2.edu%22%2C%22bandwidth%22%3A%220%22%2C%22name%22%3A%22sense-connection%22%2C%22description%22%3A%22test_sense%22%2C%22tag%22%3A%222560%22%2C%22interface%22%3A%22HundredGigE0%5C%2F0%5C%2F0%5C%2F26%22%7D"
#command="$command_root \"$command_url/$command_cat?method=$method&$param&$param1&$param2&$param3&$param4&$param5\""


echo $command
eval $command
