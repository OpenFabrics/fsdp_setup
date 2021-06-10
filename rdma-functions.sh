#!/bin/bash

get_file machines/wwns
get_file machines/nfs-mounts

###########################################################################
#
# Network Specifications
#
# The following variables define the network setup of the cluser
# on the fabics, etc.
###########################################################################

# If set, this will set the domain-name option in the DHCP 
# and interface configurations
domain_name="ofa.iol.unh.edu"

# If set, this will set the DNS servers optins in the DHCP and 
# interface configurations
domain_name_servers=("10.12.2.254")

# IPv4 prefix for fabric neworks (i.e. 172.31.x.0/24)
network_prefix="172.31" 

# Networks (IPMI, lights-out, etc.) used in the lab
lab_networks="10.12.0.0/16"


# Defines of all our network fabrics so we don't have to define these
# in multiple places.  Format is, label.subnet, where subnet is defined
# as x in the network prefix above.  As many or as few as 1 network can be 
# defined as needed.  Note, all fabric IPv4 networks are assumed to be /24 size.

# Infiniband Fabric 1
ib0_2k_nets=(ib0 ib0.2 ib0.4 ib0.6)
#ib0_4k_nets=(ib0.10 ib0.12 ib0.14 ib0.16)
ib0_nets=(${ib0_2k_nets[*]} ${ib0_4k_nets[*]})

# InfiniBand Fabric 2
#ib1_2k_nets=(ib1 ib1.3 ib1.5 ib1.7)
#ib1_4k_nets=(ib1.9 ib1.11 ib1.13)
#ib1_nets=(${ib1_2k_nets[*]} ${ib1_4k_nets[*]})

# OmniPath Fabric 1
opa0_nets=(opa0 opa0.22)

# OmniPath Fabric 2
#opa1_nets=(opa1 opa1.23 opa1.25)

# ROCE Fabric 1
roce_nets=(roce roce.43 roce.45)

# iWARP Fabric 1
iw_nets=(iw iw.51 iw.52)

all_nets=(${ib0_nets[*]} ${ib1_nets[*]} ${opa0_nets[*]} ${opa1_nets[*]} ${roce_nets[*]} ${iw_nets[*]})

__restart_config_options() {
	local file="$1"
	local tag="$2"
	sed -e '/^# Begin '"$tag"'$/,/^# End '"$tag"'$/d' -i "$file"
	echo "# Begin $tag" >> "$file"
}

__write_config_option() {
	local file="$1"
	local option="$2"
	echo "$option" >> "$file"
}

__end_config_options() {
	local file="$1"
	local tag="$2"
	echo "# End $tag" >> "$file"
}

# Set_Config_Options - Adds custom configuration to the specified file
#   while making sure not to add the same information twice
# Args:
#  @file - Config file to edit
#  @tag - Unique string to identify start/end of config options in file
#  @options - String to put between the tags in the file
Set_Config_Options() {
	local file="$1"
	local tag="$2"
	local options="$3"
	[ -z "$file" -o -z "$tag" -o -z "$options" ] && return
	[ ! -f "$file" ] && return
	__restart_config_options "$file" "$tag"
	__write_config_option "$file" "$options"
	__end_config_options "$file" "$tag"
}

Disable_Target() {
	[ -f /lib/systemd/system/$1.target ] && systemctl disable $1.target
}

Enable_Target() {
	[ -f /lib/systemd/system/$1.target ] && systemctl enable $1.target
}

Start_Service() {
	[ -f /etc/rc.d/init.d/$1 ] && service $1 start
	[ -f /lib/systemd/system/$1.service ] && systemctl start $1.service
}

Stop_Service() {
	[ -f /etc/rc.d/init.d/$1 ] && service $1 stop
	[ -f /lib/systemd/system/$1.service ] && systemctl stop $1.service
}

Disable_Service() {
	[ -f /etc/rc.d/init.d/$1 ] && chkconfig --level 2345 $1 off
	[ -f /lib/systemd/system/$1.service ] && systemctl disable $1.service
}

Enable_Service() {
	[ -f /etc/rc.d/init.d/$1 ] && chkconfig --level 2345 $1 on
	[ -f /lib/systemd/system/$1.service ] && systemctl enable $1.service
}

Restart_Service() {
	[ -f /etc/rd.d/init.d/$1 ] && service $1 restart
	[ -f /lib/systemd/system/$1.service ] && systemctl restart $1.service
}

Clear_Default_Interfaces() {
	pushd /etc/sysconfig/network-scripts >/dev/null
	for file in ifcfg-*; do
		if [ "$file" != "ifcfg-lo" ]; then
			rm -f $file
		fi
	done
	popd >/dev/null
}

Clear_Rdma_Interfaces() {
	pushd /etc/sysconfig/network-scripts >/dev/null
	rm -f ifcfg-cxgb* ifcfg-ib* ifcfg-qib* ifcfg-mlx* ifcfg-mthca* ifcfg-usnic* ifcfg-ocrdma*
	popd >/dev/null
}

Nmcli_Con_Reload() {
	[ -x /usr/bin/nmcli ] && nmcli con reload
}

Create_Fixed_Addresses() {
	i=0
	for fabric in $*; do
		for subnet in ${all_nets[*]}; do
			net_part=`echo $subnet | cut -f 1 -d '.'`
			__if_x_in_y $fabric $net_part || continue
			IPS[$i]=`grep -w ${subnet}-${host_part} /etc/hosts | awk '{print $1}'`
			let i++
		done
	done
}

Create_Interface() {
	declare bootproto="" ipaddr="" network="" broadcast="" stp=""
	declare mtu="" vlan="" pkey="" connected_mode="" hwaddr="" defroute="no"
	declare mac="" netmask="255.255.255.0" priority="" master=""
	if [[ $# -lt 3 ]]; then
echo "Usage: $FUNCNAME <physdev> <type> <onboot> ..."
echo "	[[static IPADDR] | [dhcp [defroute]]]"
echo "	[bridge BRIDGE] [master MASTER] [stp yes|no] [priority PRIORITY]"
echo "	[hwaddr HWADDR] [vlan vlan_id] [mac HWADDR] [mtu MTU]"
echo "	[pkey pkey_id] [connected_mode yes|no]"
echo
echo "  @physdev - the name that you want the physical device to have"
echo "  	(system names like eth0/ib0 are discouraged as they may clash"
echo "		with what the kernel picks for other devices, and there is a"
echo "		standard to name devices em# for the network interfaces"
echo "		embedded on the	motherboard, and p#p# for devices on the PCI"
echo "		bus).  Udev will rename devices to the physdev name if you"
echo "		specify the hwaddr and it matches the native hwaddr of the"
echo "		device.  However, Udev does not handle IPoIB devices for you"
echo "		automatically like it does Ethernet devices, so we create an"
echo "		entry in /etc/udev/rules.d/70-persistent-ipoib.rules for the"
echo "		IPoIB devices if they have a HWADDR entry given."
echo "		In the case of vlans, the physdev is the real dev the vlan"
echo "		is being added onto, and the vlan device will end up being"
echo "		named physdev.vlan_id.  For IPoIB P_Key devices, the pkey_id"
echo "		can be given in decimal or in hex, but it will always be"
echo "		converted to hex before the device is created and the name"
echo "		will use the hex version of the number.  If you want to pass"
echo "		the vlan_id in hex, you must use the 0x prefix."
echo "	@type - Interface type: Ethernet, Vlan, InfiniBand, Bridge, Team, Bond"
echo "	@onboot - Yes|No, should we start this interface automatically"
echo "	@static - Statically defined network interface, netmask for all"
echo "		fabrics in test cluster is always 255.255.255.0, so we only"
echo "		need the IPADDR of this interface, we can calculate the rest"
echo "	@dhcp - Use dhcp on interface, not supported on all types and all"
echo "		releases, we will attempt to fall back to static when we"
echo "		know it isn't available.  The optional defroute item tells"
echo "		us to treat this interface as the default route interface"
echo "	!@static and !@dhcp - When neither a static address or dhcp is given"
echo "		we will set BOOTPROTO=none and disable IPV4 and IPV6 on the"
echo "		interface"
echo "	@stp - Only relevant on Bridge master devices, should we enable the"
echo "		Spanning Tree Protocol, yes or no"
echo "	@priority - Only relevant for Bridge masters or slaves, sets the"
echo "		priority of this device in the spanning tree messages"
echo "	@bridge - This is given on a bridge slave device to enslave it to"
echo "		the named bridge"
echo "  @master - Passed in on slave devices, this links the slave to the"
echo "          named master (regardless of type of master, works on bridges,"
echo "          teams, and bonds alike).  Use of the bridge setting is"
echo "          deprecated and the new master option is the preferred usage"
echo "	@hwaddr - Physical address of device (MAC address for Ethernet,"
echo "		fake MAC address for IPoIB interfaces, HWADDR of slaves to"
echo "          bridge and team devices)"
echo "	@vlan - Create a vlan interface using vlan_id as the number and"
echo "		physdev as the parent device"
echo "  @mac - Use the listed HWADDR for the device.  Mainly applicable to"
echo "          the various subdevices (like vlan interfaces) and masters"
echo "          (such as bridge, team, and bond devices).  This allows you"
echo "          to give those devices a unique address.  This is separate"
echo "          from hwaddr which is used to tie a configuration to a specific"
echo "          piece of hardware."
echo "	@pkey - Create an IPoIB P_Key based device (like a vlan)."
echo "	@mtu - MTU of device.  For vlans, this means nothing as MTU is set"
echo "		on parent device."
echo "	@connected_mode - Whether or not to use connected mode on IPoIB"
echo "		interfaces.  Defaults to no."
		return 1
	fi

	physdev=$1
	iftype=$2
	onboot=$3
	shift 3
	while [[ $# != 0 ]]; do
		case $1 in
			dhcp)
				bootproto=$1
				shift;;
			static)
				bootproto=$1
				ipaddr=$2
				shift 2;;
			mtu)
				mtu=$2
				shift 2;;
			vlan)
				vlan=$2
				shift 2;;
			pkey)
				pkey=$2
				shift 2;;
			connected_mode)
				connected_mode=$2
				shift 2;;
			hwaddr)
				hwaddr=$2
				shift 2;;
			defroute)
				defroute=yes
				shift;;
			mac)
				mac=$2
				shift 2;;
			bridge|master)
				master=$2
				shift 2;;
			stp)
				stp=$2
				shift 2;;
			priority)
				priority=$2
				shift 2;;
			*)
				echo "Unknown option ($1) passed to CreateInterface"
				shift;;
		esac
	done
	[ "$iftype" = infiniband ] && iftype=InfiniBand
	# rhel5 doesn't support InfiniBand P_Key vlans properly, so skip them
	[ "$OS" = rhel -a "$RELEASE" -lt 6 -a "$iftype" = InfiniBand -a -n "$pkey" ] && return 0
	devname="${physdev}"
	if [ -n "${vlan}" ]; then
		devname="${physdev}.${vlan}"
	fi
	if [ -n "${pkey}" ]; then
		hex_pkey=$(printf "0x%d" $pkey)
		devname="${physdev}.$(printf "%04x" $(( 0x8000 | ${hex_pkey} )) )"
#		devname="${physdev}.${pkey}"
	fi
	output=/etc/sysconfig/network-scripts/ifcfg-$devname
	# Check if we are set to use dhcp and are installing a
	# release that doesn't support dhcp on IB.  We can use
	# dhcp on rhel6 or later, and on Fedora 17(?) or 18 or later,
	# but not on Fedora 16 or earlier
	if [ "$OS" = "rhel" -a "$RELEASE" -lt 6 -a "$bootproto" = "dhcp" -a "$defroute" = "no" ]; then
		fabric=`echo "$devname" | cut -f 2- -d '_' | sed -e 's/800//'`
		ipaddr=`grep ${fabric}-${host_part} /etc/hosts | awk '{print $1}'`
		[ -n "$ipaddr" ] && bootproto=static
	fi
	if [ "$iftype" = InfiniBand -a "$bootproto" = dhcp ]; then
		if [ $OS = fedora -a $RELEASE -lt 17 ] || [ $OS = rhel -a $RELEASE -lt 6 ]; then
			fabric=`echo "$devname" | cut -f 2- -d '_' | sed -e 's/800//'`
			ipaddr=`grep ${fabric}-${host_part} /etc/hosts | awk '{print $1}'`
			[ -n "$ipaddr" ] && bootproto=static
		fi
	fi
	if [ "$bootproto" = static ]; then
		network=`echo $ipaddr | cut -f -3 -d '.'`.0
		broadcast=`echo $ipaddr | cut -f -3 -d '.'`.255
	fi
	echo "DEVICE=${devname}" > $output
	if [ -n "${vlan}" ]; then
		echo "VLAN=yes" >> $output
		echo "VLAN_ID=${vlan}" >> $output
		# echo "REORDER_HDR=0" >> $output
		[ "${vlan}" -eq 43 ] && echo "VLAN_EGRESS_PRIORITY_MAP=0:3,1:3,2:3,3:3,4:3,5:3,6:3,7:3" >> $output
		[ "${vlan}" -eq 45 ] && echo "VLAN_EGRESS_PRIORITY_MAP=0:5,1:5,2:5,3:5,4:5,5:5,6:5,7:5" >> $output
	fi
	if [ -n "${pkey}" ]; then
		echo "PHYSDEV=${physdev}" >> $output
		echo "PKEY=yes" >> $output
		echo "PKEY_ID=${hex_pkey}" >> $output
	fi
	[ -n "${mac}" ] && echo "MACADDR=${mac}" >> $output
	echo "TYPE=${iftype}" >> $output
	case $iftype in
		Bond)
			echo "BONDING_OPTS=\"downdelay=0 miimon=100 mode=802.3ad updelay=0\"" >> $output
			echo "BONDING_MASTER=yes" >> $output
			echo "AUTOCONNECT_SLAVES=yes" >> $output
			;;
		Team)
			echo "DEVICETYPE=Team" >> $output
			echo "AUTOCONNECT_SLAVES=yes" >> $output
			echo 'TEAM_CONFIG="{\"runner\": {\"name\": \"lacp\", \"active\": true, \"fast_rate\": true, \"tx_balancer\": {\"name\": \"basic\"}, \"tx_hash\": [\"eth\", \"ipv4\", \"ipv6\"]}, \"link_watch\": {\"name\": \"ethtool\"}}"' >> $output
			;;
		Bridge)
			[ -n "${priority}" ] && echo "BRIDGING_OPTS=priority=${priority}" >> $output
			[ -n "${stp}" ] && echo "STP=${stp}" >> $output
			;;
		Ethernet)
			case "${master}" in
				*bond*)
					echo "MASTER=${master}" >> $output
					echo "SLAVE=yes" >> $output
					;;
				*bridge*|br[0123456789]_*)
					echo "BRIDGE=${master}" >> $output
					;;
				*team*)
					echo "TEAM_MASTER=${master}" >> $output
					echo "DEVICETYPE=TeamPort" >> $output
					;;
			esac
			;;
	esac
	[ ${iftype} = "InfiniBand" ] && [ "$OS" = "rhel" -a "$RELEASE" -lt 7 ] && echo "NM_CONTROLLED=No" >> $output
	[ ${iftype} = "InfiniBand" ] && [ "$OS" = "fedora" -a "$RELEASE" -lt 20 ] && echo "NM_CONTROLLED=No" >> $output
	echo "ONBOOT=${onboot}" >> $output
	[ -n "${hwaddr}" ] && echo "HWADDR=${hwaddr}" >> $output
	if [ -n "${ipaddr}" ]; then
		echo "BOOTPROTO=${bootproto}" >> $output
		echo "IPADDR=${ipaddr}" >> $output
		echo "NETMASK=${netmask}" >> $output
		echo "NETWORK=${network}" >> $output
		echo "BROADCAST=${broadcast}" >> $output
		echo "IPV4_FAILURE_FATAL=yes" >> $output
		echo "PEERDNS=no" >> $output
		echo "IPV6INIT=yes" >> $output
		echo "IPV6_AUTOCONF=yes" >> $output
		echo "IPV6_DEFROUTE=no" >> $output
		echo "IPV6_PEERDNS=no" >> $output
		echo "IPV6_PEERROUTES=yes" >> $output
		echo "IPV6_FAILURE_FATAL=no" >> $output
	elif [ -n "${bootproto}" ]; then
		echo "BOOTPROTO=${bootproto}" >> $output
		echo "DEFROUTE=${defroute}" >> $output
		if [ "${defroute}" = "yes" ]; then
			echo "PEERDNS=yes" >> $output
			echo "SEARCH=\"lab.bos.redhat.com bos.redhat.com devel.redhat.com redhat.com\"" >> $output
		else
			echo "PEERDNS=no" >> $output
		fi
		echo "PEERROUTES=yes" >> $output
		echo "IPV4_FAILURE_FATAL=yes" >> $output
		echo "IPV6INIT=yes" >> $output
		echo "IPV6_AUTOCONF=yes" >> $output
		echo "IPV6_DEFROUTE=no" >> $output
		echo "IPV6_PEERDNS=no" >> $output
		echo "IPV6_PEERROUTES=yes" >> $output
		echo "IPV6_FAILURE_FATAL=no" >> $output
	else
		echo "BOOTPROTO=none" >> $output
		echo "DEFROUTE=no" >> $output
		echo "PEERDNS=no" >> $output
		echo "PEERROUTES=no" >> $output
		echo "IPV4_FAILURE_FATAL=no" >> $output
		echo "IPV4INIT=no" >> $output
		echo "IPV6INIT=no" >> $output
	fi
	[ -n "${mtu}" ] && echo "MTU=${mtu}" >> $output
	[ -n "${connected_mode}" ] && echo "CONNECTED_MODE=${connected_mode}" >> $output
	echo "NAME=${devname}" >> $output
	if [ "${iftype}" = "InfiniBand" ]; then
		output=/etc/udev/rules.d/70-persistent-ipoib.rules
		match_addr=$(echo $hwaddr | tail -c 24)
	else
		output=/etc/udev/rules.d/70-persistent-net.rules
		match_addr=$(echo $hwaddr)
	fi
	if [ ! -f $output ]; then
		touch $output
	fi
	[ $OS = rhel -a $RELEASE -gt 5 -a -n "${hwaddr}" -a -z "$pkey" ] && ( sed -e "/$match_addr/d" -i $output; echo "ACTION==\"add\", SUBSYSTEM==\"net\", DRIVERS==\"?*\", ATTR{type}==\"32\", ATTR{address}==\"?*${match_addr}\", NAME=\"$physdev\"" >> $output )
	[ $OS = fedora -a $RELEASE -gt 16 -a -n "${hwaddr}" -a -z "$pkey" ] && ( sed -e "/$match_addr/d" -i $output; echo "ACTION==\"add\", SUBSYSTEM==\"net\", DRIVERS==\"?*\", ATTR{type}==\"32\", ATTR{address}==\"?*${match_addr}\", NAME=\"$physdev\"" >> $output )
}

Create_Multicast_Route() {
	if [ "$OS" = rhel -a "$RELEASE" -lt 6 ]; then
		# Don't yet know how to accomplish this when we don't have
		# NetworkManager as our network agent
		echo "Can't create a multicast route, NetworkManager isn't used"
		echo "in this release as our default network control agent."
		return
	fi
	# Create a NetworkManager dispatcher event to create the route
	cat > /etc/NetworkManager/dispatcher.d/99-multicast.conf <<EOF
#!/bin/sh
interface=\$1
status=\$2
[ "\$interface" = $1 ] || exit 0
case \$status in
up)
	ip route add 224.0.0.0/4 dev \$interface
	;;
esac
EOF
	chmod +x /etc/NetworkManager/dispatcher.d/99-multicast.conf
}

# $1 - Parent interface name
Create_Target_Restart_Dispatcher() {
	if [ "$OS" = rhel -a "$RELEASE" -lt 6 ]; then
		# Don't yet know how to accomplish this when we don't have
		# NetworkManager as our network agent
		echo "Can't create a NetworkManager dispatcher as NM isn't used"
		echo "in this release as our default network control agent."
		return
	fi
	cat > /etc/NetworkManager/dispatcher.d/99-restart-target.conf <<EOF
#!/bin/sh
interface=\$1
status=\$2
case \$status in
up)
	systemctl restart target
	;;
esac
EOF
	chmod +x /etc/NetworkManager/dispatcher.d/99-restart-target.conf
}

# $1 - Parent interface name
# $2 - Vlan interface name
# $3 - Priority
Create_Pfc_Egress_Dispatcher() {
	if [ "$OS" = rhel -a "$RELEASE" -lt 6 ]; then
		# Don't yet know how to accomplish this when we don't have
		# NetworkManager as our network agent
		echo "Can't create a NetworkManager dispatcher as NM isn't used"
		echo "in this release as our default network control agent."
		return
	fi
	prios="$3 $3 $3 $3 $3 $3 $3 $3 $3 $3 $3 $3 $3 $3 $3 $3"
	user_prios="$3,$3,$3,$3,$3,$3,$3,$3,$3,$3,$3,$3,$3,$3,$3,$3"
	case $1 in
	ocrdma_roce)
		num_tc="num_tc 8"
		queues="queues 1@0 1@1 1@2 1@3 1@4 1@5 1@6 1@7"
		;;
	mlx4_roce)
		num_tc="num_tc 8"
		queues="queues 32@0 32@32 32@64 32@96 32@128 32@160 32@192 32@224"
		;;
	mlx5_roce)
		num_tc="num_tc 8"
		queues=""
		;;
	esac
	# Create a NetworkManager dispatcher
	cat > /etc/NetworkManager/dispatcher.d/98-${2}-egress.conf <<EOF
#!/bin/sh
interface=\$1
status=\$2
[ "\$interface" = $2 ] || exit 0
case \$status in
up)
	tc qdisc add dev $1 root mqprio $num_tc map $prios $queues
	# tc_wrap.py -i $1 -u $user_prios
	;;
esac
EOF
	chmod +x /etc/NetworkManager/dispatcher.d/98-${2}-egress.conf
}

__get_net_from_subnet() {
	# Requires: name of fabric
	# Returns: network address of fabric
	case $1 in
		ib0)
			net=0
			;;
		ib1)
			net=1
			;;
		opa0)
			net=20
			;;
		opa1)
			net=21
			;;
		roce)
			net=40
			;;
		iw)
			net=50
			;;
		*)
			net=`echo $1 | cut -f 2 -d '.'`
			;;
	esac
}

__if_x_in_y() {
	[ -z "$1" ] && return 1
	[ -z "$2" ] && return 1
	for tmp in $2; do
		[ "${tmp}" = "$1" ] && return
	done
	return 1
}

__create_rdma_interfaces_usage() {
echo "Usage: $FUNCNAME <dev> <fabric> <guid/mac> <dhcp/host byte of IP address>"
echo "           [<slavedev> <hwaddr>]..."
echo
echo "  @dev - the name that you want the physical device to have"
echo "  	(system names like eth0/ib0 are discouraged as they may clash"
echo "		with what the kernel picks for other devices, and there is a"
echo "		standard to name devices em# for the network interfaces"
echo "		embedded on the	motherboard, and p#p# for devices on the PCI"
echo "		bus).  Standard in the Westford cluster is to use the driver"
echo "          name as the dev name (mlx4, qib, cxgb4, etc.).  However, it"
echo "          can also be a bond or a team or a bridge device name.  If it"
echo "          is any of those three composite devices, then there must be"
echo "          at least one slavedev/hwaddr pair added to the command, but"
echo "          there may be more than one pair."
echo "          In order to trigger bond, bridge, or team processing, the dev"
echo "          name must be formatted properly:"
echo "            Bond: includes the full word bond anywhere in the name"
echo "            Bridge: is br and a single digit number, or includes the"
echo "             full word bridge anywhere in the dev name"
echo "            Team: includes the full word team anywhere in the name"
echo "  @fabric - One of our supported RDMA fabric types: ib0, ib1, roce,"
echo "          iwarp, opa0"
echo "  @guid/mac - A valid MAC address for Ethernet devices or Ethernet"
echo "          metadevices like bridge or bond.  On Ethernet devices, this"
echo "          will end up passed as HWADDR, on metadevices it will be the"
echo "          metadevice's MACADDR entry.  For IB and OPA devices, a valid"
echo "          IPoIB guid which is used by the udev renaming to tie the"
echo "          requested name to the device and also by configuration file"
echo "          to tie our configuration to our specific hardware."
echo "  @dhcp/host byte of IP address - Either dhcp or the final byte of our"
echo "          static IP address to be used on the RDMA interface"
echo "  @slavedev @hwaddr - These must be specified in pairs.  The slavedev"
echo "          will become the name of the Ethernet device we are adding"
echo "          to the metadevice and the hwaddr will be used on the slave"
echo "          Ethernet device as the HWADDR entry in the file to tie the"
echo "          configuration to the specific Ethernet device."
}

Create_Rdma_Interfaces() {
	if [ $# -lt 4 ]; then
		__create_rdma_interfaces_usage
		return 1
	fi

	CM=""
	TYPE=InfiniBand
	HWADDR=hwaddr
	__get_net_from_subnet $2
	start_net=$net
	case "$2" in
	ib0)
		[ "$1" != "mlx5" ] && CM="connected_mode yes"
		nets=(${ib0_2k_nets[*]} ${ib0_4k_nets[*]})
		__get_net_from_subnet ${ib0_4k_nets[0]}
		_4k_start=$net
		;;
	ib1)
		nets=(${ib1_2k_nets[*]} ${ib1_4k_nets[*]})
		__get_net_from_subnet ${ib1_4k_nets[0]}
		_4k_start=$net
		;;
	opa0)
		nets=(${opa0_nets[*]})
		CM="connected_mode yes"
		;;
	opa1)
		nets=(${opa1_nets[*]})
		CM="connected_mode yes"
		;;
	roce)
		TYPE=Ethernet
		nets=(${roce_nets[*]})
		MTU="mtu ${SYSTEM_MTU:-9000}"
		;;
	iw)
		TYPE=Ethernet
		nets=(${iw_nets[*]})
		MTU="mtu ${SYSTEM_MTU:-9000}"
		;;
	*)
		echo "Unknown fabric type passed to Create_Rdma_Interfaces"
		;;
	esac
	case "$1" in
		*bond*)
			TYPE=Bond
			parent="$1_$2"
			HWADDR=mac
			;;
		*team*)
			TYPE=Team
			parent="$1_$2"
			HWADDR=mac
			;;
		*bridge*|br[0123456789])
			TYPE=Bridge
			parent="$1_$2"
			HWADDR=mac
			;;
	esac

	if [ $HWADDR = "mac" -a $# -lt 6 ]; then
		__create_rdma_interfaces_usage
		return 1
	fi

	for subnet in ${nets[*]}; do
		__get_net_from_subnet $subnet
		if [ "$4" = "dhcp" ]; then
			BP=dhcp
		else
			BP="static ${network_prefix}.$net.$4"
		fi
		if [ "$TYPE" = "InfiniBand" ]; then
			if [ -z "$CM" ]; then
				[ $net -lt $_4k_start ] && MTU="mtu 2044" || MTU="mtu 4092"
			else
				MTU="mtu 65520"
			fi
		fi
		if [ $net = $start_net ]; then
			Create_Interface $1_$2 $TYPE yes $HWADDR $3 $BP $CM $MTU
		else
			case $TYPE in
			InfiniBand)
				Create_Interface $1_$2 $TYPE yes $HWADDR $3 $BP $CM $MTU pkey $net
				;;
			Ethernet|Bond|Team)
				Create_Interface $1_$2 Vlan yes $BP vlan $net
				[ "$2" != "iw" ] && Create_Pfc_Egress_Dispatcher $1_$2 $1_$2.$net $(($net - $start_net))
				;;
			esac
		fi
	done

	# shift out our parent config and check for slave pairs
	shift 4
	while [ $# -ge 2 ]; do
		Create_Interface $1 Ethernet yes hwaddr $2 master $parent
		shift 2
	done
}

# Append the aliases to /etc/hosts..
Update_Etc_Hosts() {

	FILE="/etc/hosts"
	cat > $FILE <<EOF
127.0.0.1	localhost localhost.localdomain localhost4 localhost4.localdomain4
::1	localhost localhost.localdomain localhost6 localhost6.localdomain6
10.16.45.105		rdma-master
EOF

	local __awk_src='
BEGIN {
	offset["qe"]=0
	offset["cki"]=80
	offset["dev"]=100
	offset["perf"]=180
	offset["virt"]=200
	offset["storage"]=220
	offset["cert"]=230
	offset["dhcp"]=240
	offset["ocp-director"]=253
	offset["rdma-master"]=254
	net["ib0", 0]="ib0"
	net["ib0", 2]="ib0.2"
	net["ib0", 4]="ib0.4"
	net["ib0", 6]="ib0.6"
	net["ib0", 8]="ib0.8"
	net["ib0", 10]="ib0.10"
	net["ib0", 12]="ib0.12"
	net["ib0", 14]="ib0.14"
	net["ib0", 16]="ib0.16"
	net["ib1", 1]="ib1"
	net["ib1", 3]="ib1.3"
	net["ib1", 5]="ib1.5"
	net["ib1", 7]="ib1.7"
	net["ib1", 9]="ib1.9"
	net["ib1", 11]="ib1.11"
	net["ib1", 13]="ib1.13"
	net["opa0", 20]="opa0"
	net["opa0", 22]="opa0.22"
	net["opa0", 24]="opa0.24"
	net["opa1", 21]="opa1"
	net["opa1", 23]="opa1.23"
	net["opa1", 25]="opa1.25"
	net["roce", 40]="roce"
	net["roce", 43]="roce.43"
	net["roce", 45]="roce.45"
	net["iw", 50]="iw"
	net["iw", 51]="iw.51"
	net["iw", 52]="iw.52"
}
{
	num_host_fields = split($1, host_fields, "-")
	switch($1) {
		case "rdma-master":
			host_part = $1
			host_ip = offset[host_part]
			break
		case "rdma-ocp-director":
			host_part = "ocp-director"
			host_ip = offset[host_part]
			break
		default:
			host_part = substr($1, index($1, "-") + 1)
			group = host_fields[2]
			host_ip = offset[group] + host_fields[num_host_fields]
			break
	}
	for (i=2; i<=NF; i++) {
		for (j=0; j<=254; j++) {
			if (($i, j) in net) {
				net_ip = j
				net_name = net[$i, j]
				printf("'"${network_prefix}"'.%d.%d\t\t%s-%s\n", net_ip,
					host_ip, net_name, host_part)
			}
		}
	}
}
'
	get_file machines/host-fabrics
	awk "$__awk_src" host-fabrics >> $FILE

	return 0
}

# ppc64 uses efi, in a way, but it's of efi, not UEFI, and it uses it via
# grub2 and not via the UEFI tools
Fix_Boot_Loader() {
if [ -x /usr/sbin/efibootmgr ]; then
	# not much to do here for UEFI...our bashrc file takes care of this
	# for us, so just save our EFI state in case we want to look at it
	# later
	efibootmgr > /root/EFI_SETUP_POST_INSTALL.TXT
elif [ -x /usr/sbin/grub2-mkconfig ]; then
	deffile=/etc/default/grub
	cfgfile=/boot/grub2/grub.cfg
	cp $deffile $deffile.orig
	GCL=`grep CMDLINE $deffile | sed -e 's/GRUB_CMDLINE_LINUX=//;s/"//g'`
	if [ -n "$HOST_GRUB_OPTIONS" ]; then
		GCL=`echo $GCL | sed -e "s/$HOST_GRUB_OPTIONS//g"`
	fi
	GCL=`echo $GCL | sed -e 's/console=tty0 //g;s/rd_NO_PLYMOUTH //g'`
	sed -e '/GRUB_TIMEOUT.*$/ d;/GRUB_CMDLINE_LINUX.*$/ d' -i $deffile
	echo "GRUB_TIMEOUT=10" >> $deffile
	echo "GRUB_CMDLINE_LINUX=\"$HOST_GRUB_OPTIONS console=tty0 rd_NO_PLYMOUTH $GCL\"" >> $deffile
	grub2-mkconfig -o $cfgfile
	if [ $ARCH_FAMILY = x86 ]; then
		grub2-install --recheck --force /dev/sda
	fi
elif [ -f /boot/grub/grub.conf ]; then
	# When using the original grub on a Dell machine with console
	# redirection enabled, you need to remove the terminal line
	# from the grub.conf or it messes up grub.
	if [ "`dmidecode -s system-manufacturer | cut -c 1-4`" = "Dell" ]; then
		sed -e '/^terminal.*$/ d' -i /boot/grub/grub.conf
	fi
fi
}

Setup_FSDP_Mounts() {
	Set_Config_Options /etc/fstab "internal FSDP mounts" ""
}

Setup_Nfs_Client_Mounts() {
	local opt_tag="RDMA nfs client mounts"
	__restart_config_options /etc/fstab "$opt_tag"
	if [ "$RDMA_HOST" != "rdma-master" ]; then
		# Everyone mounts /srv/repos via ethernet
		mkdir -p /srv/rdma-master/repos
		__write_config_option /etc/fstab "rdma-master:/srv/NFSoRDMA/repos	/srv/rdma-master/repos	nfs4	defaults,rw,tcp,hard,intr,nfsvers=4.1,noauto"
	fi
	for server in $NFSServers; do
		[ "$server" = "$RDMA_HOST" ] && continue
		sserver=`echo $server | cut -f 2- -d '-' -`
		for fabric in ${NFSFabrics[$server]}; do
			__if_x_in_y "$fabric" "${HOST_FABRICS[*]}" || continue
			for ver in ${NFSProtos[$server]}; do
				for mpt in ${NFSMPoints[$server]}; do
					mkdir -p /srv/$server/$fabric/$ver-$mpt-${NFSIntDevs[$server-$fabric]}
					__write_config_option /etc/fstab "${fabric}-$sserver:/srv/NFSoRDMA/$ver-$mpt	/srv/$server/$fabric/$ver-$mpt-${NFSIntDevs[$server-$fabric]}	${NFSMOpts[$ver]}"
				done
			done
		done
	done
	__end_config_options /etc/fstab "$opt_tag"
}

Stop_Nfs_Server() {
	Stop_Service nfs-server
	Stop_Service nfs
	Stop_Service nfs-rdma
	Stop_Service nfs-idmap
	Stop_Service nfs-lock
	Stop_Service nfs-mountd
}

Disable_Nfs_Server() {
	Disable_Service nfs
	Disable_Service nfs-rdma
	Disable_Service nfs-idmap
	Disable_Service nfs-lock
	Disable_Service nfs-mountd
	Disable_Service nfs-server
}

Enable_Nfs_Server() {
	Enable_Service nfs-idmap
	Enable_Service nfs-lock
	Enable_Service nfs-mountd
	Enable_Service nfs-server
	Enable_Service nfs
	Enable_Service nfs-rdma
}

Setup_Nfs_Server() {
	# Depending on the OS release, the NFSoRDMA server might be configured by
	# /etc/sysconfig/nfs or by /etc/rdma/rdma.conf, so set the port in both
	sed -e 's/#RDMA_PORT=.*/RDMA_PORT=20049/;s/.*RPCNFSDARGS=.*$/RPCNFSDARGS="--rdma=20049"/' -i /etc/sysconfig/nfs
	sed -e 's/NFSoRDMA_LOAD=.*/NFSoRDMA_LOAD=yes/;s/NFSoRDMA_PORT=.*/NFSoRDMA_PORT=20049/' -i /etc/rdma/rdma.conf
	Enable_Nfs_Server
}

# Export names are expected to be in v#-name format by the client mount code
# above.
Setup_Nfs_Exports() {
	for export in $*; do
		mkdir -p /srv/NFSoRDMA/$export
		mount /srv/NFSoRDMA/$export
		sed -e '/'"${export}"'/ d' -i /etc/exports
		echo "/srv/NFSoRDMA/$export	${network_prefix}.0.0/16(rw,async,insecure,no_root_squash,mp) rdma-*(rw,async,insecure,no_root_squash,mp)" >> /etc/exports
	done
}

__setup_iser_client_path() {
	local server="$1"
	local fabric="$2"
	local backstore="$3"
	local path_num=$4
	local server_part=`echo $server | cut -f 2- -d '-' -`
	local target=${iqn}:$server
	local portal=$fabric-$server_part
	local wwn="${iqn}:$RDMA_HOST"
	# We have auto mapped luns turned off, so we also map our specific lun
	# to our ACL
	ssh $server "targetcli ls /iscsi/$target/tpg1/acls" | grep $wwn >/dev/null 2>&1
	[ $? -eq 1 ] && ssh $server "targetcli /iscsi/$target/tpg1/acls create $wwn; targetcli saveconfig"
	lun_stat=`ssh $server "targetcli ls /iscsi/$target/tpg1/acls/$wwn"`
	lun=`echo $lun_stat | wc -l`
	let lun--
	echo $lun_stat | grep iser-$backstore >/dev/null 2>&1
	[ $? -eq 1 ] && ssh $server "targetcli /iscsi/$target/tpg1/acls/$wwn create $lun /backstores/block/iser-$backstore; targetcli saveconfig"
	# Log us out
	iscsiadm -m node -I iser -p $portal -u
	# Redo discovery
	iscsiadm -m discovery -I iser -t sendtargets -p $portal
	# Log us back in
	iscsiadm -m node -p $portal -I iser -l
	if [ $path_num -eq 0 ]; then
		mkdir -p /srv/$server/iser-$backstore
	fi
}

__create_iser_client_usage() {
echo -e "
Usage:

Create_Iser_Client_Devices <server> <backstore> [fabrics ...]
\tserver - Required, we will ssh to this server to add ourselves to the
\t  ACLs and map our LUN
\tbackstore - name of backstore device to use on server.  The name must
\t  start with iser- in the actual /backstores/block directory on the
\t  server, but the iser- portion of the name must not be included in the
\t  name passed here as it will be pre-pended later.
\tfabric - One or more fabrics you wish to enable access to the LUN via.
\t  The fabrics will be checked to make sure that both the server and
\t  this host have connections to the fabrics.  If no fabrics are
\t  specified, then the union of all fabrics for the server and this
\t  host will be used.  If there is more than one fabric configured,
\t  multipath will be enabled by default."
}

# Call this to set up possible iSER device definitions.
Create_Iser_Client_Devices() {
	if [ $# -lt 2 ]; then
		__create_iser_client_usage
		return
	fi
	local server="$1"
	local backstore="$2"
	shift 2
	local paths=""
	local num_paths=0
	echo "InitiatorName=${iqn}:$RDMA_HOST" > /etc/iscsi/initiatorname.iscsi
	__if_x_in_y "$server" "${ISER_SERVERS[*]}" || return
	[ -n "$1" ] && paths="$*" || paths="${ISER_FABRICS[$server]}"
	for fabric in $paths; do
		__if_x_in_y "$fabric" "${HOST_FABRICS[*]}" || continue
		__if_x_in_y "$fabric" "${ISER_FABRICS[$server]}" || continue
		__setup_iser_client_path "$server" "$fabric" "$backstore" $num_paths
		let num_paths++
	done
	if [ $num_paths -gt 1 ]; then
		if [ ! -f /etc/multipath.conf ]; then
			cp /usr/share/doc/device-mapper-multipath*/multipath.conf /etc
		fi
		Enable_Service multipathd
		Start_Service multipathd
	fi
}

# ssh to srp target to add an ACL for this client
# targetcli uses srp names of the format:
# "ib.<32 hex chars>"
# for both target wwn and client wwn.
__setup_srp_client_path() {
	local server="$1"
	local fabric="$2"
	local backstore=$3
	local path_num=$4
	local dgid=${SRP_DGID[$server-$fabric]}
	local var_file=/etc/rdma/srp_client_variables
	local tmp_conf=/etc/rdma/srp_client_tmp_conf
	local conf_file=/etc/srp_daemon.conf
	echo -e "a pkey=ffff,dgid=$dgid\nd\n" > $tmp_conf
	pushd /dev/infiniband >/dev/null
	for umad in umad*; do
		srp_daemon -n -c -o -f $tmp_conf -d ./$umad | sed -e 'y/,/\n/' > $var_file
		[ -s $var_file ] && break
	done
	local ibdev=`cat /sys/class/infiniband_mad/$umad/ibdev`
	local ibport=`cat /sys/class/infiniband_mad/$umad/port`
	rm $tmp_conf
	popd >/dev/null
	[ ! -s $var_file ] && return
	port_guid=`ibstat $ibdev $ibport | grep "Port GUID" | cut -f 2 -d 'x'`
	init_ext=`grep initiator_ext $var_file | cut -f 2 -d '='`
	sgid="${init_ext}${port_guid}"
	# We have auto mapped luns turned off, so we also map our specific lun
	# to our ACL
	ssh $server "targetcli ls /srpt/ib.$dgid/acls" | grep $sgid >/dev/null 2>&1
	[ $? -eq 1 ] && ssh $server "targetcli /srpt/ib.$dgid/acls create ib.$sgid; targetcli saveconfig"
	lun_stat=`ssh $server "targetcli ls /srpt/ib.$dgid/acls/ib.$sgid"`
	lun=`echo $lun_stat | wc -l`
	let lun--
	echo $lun_stat | grep srp-$backstore >/dev/null 2>&1
	[ $? -eq 1 ] && ssh $server "targetcli /srpt/ib.$dgid/acls/ib.$sgid create $lun /backstores/block/srp-$backstore; targetcli saveconfig"
	sed -e "/.*dgid=$dgid.*/ d" -i $conf_file
	echo "a pkey=ffff,dgid=$dgid,queue_size=512,max_cmd_per_lun=16" >> $conf_file
	rm $var_file
	if [ $path_num -eq 0 ]; then
		mkdir -p /srv/$server/srp-$backstore
	fi
}

__create_srp_client_usage() {
echo -e "
Usage:

Create_Srp_Client_Devices <server> <backstore> [fabrics ...]
\tserver - Required, we will ssh to this server to add ourselves to the
\t  ACLs and map our LUN
\tbackstore - name of backstore device to use on server.  The name must
\t  start with srp- in the actual /backstores/block directory on the
\t  server, but the srp- portion of the name must not be included in the
\t  name passed here as it will be pre-pended later.
\tfabric - One or more fabrics you wish to enable access to the LUN via.
\t  The fabrics will be checked to make sure that both the server and
\t  this host have connections to the fabrics.  If no fabrics are
\t  specified, then the union of all fabrics for the server and this
\t  host will be used.  If there is more than one fabric configured,
\t  multipath will be enabled by default."
}

# Call this to set up possible SRP device definitions.
Create_Srp_Client_Devices() {
	if [ $# -lt 2 ]; then
		__create_srp_client_usage
		return
	fi
	local server="$1"
	local backstore="$2"
	shift 2
	local paths=""
	local num_paths=0
	__if_x_in_y "$server" "${SRP_SERVERS[*]}" || return
	# Turn off the disallow all option in the config file while we do
	# our work, we restore this at the end
	Enable_Service srpd
	Stop_Service srpd
	sed -e '/^d$/ d' -i /etc/srp_daemon.conf
	[ -n "$1" ] && paths="$*" || paths="${SRP_FABRICS[$server]}"
	for fabric in $paths; do
		__if_x_in_y "$fabric" "${HOST_FABRICS[*]}" || continue
		__if_x_in_y "$fabric" "${SRP_FABRICS[$server]}" || continue
		__setup_srp_client_path "$server" "$fabric" "$backstore" $num_paths
		let num_paths++
	done
	if [ $num_paths -gt 1 ]; then
		if [ ! -f /etc/multipath.conf ]; then
			cp /usr/share/doc/device-mapper-multipath*/multipath.conf /etc
		fi
		Enable_Service multipathd
		Start_Service multipathd
	fi
	echo "d" >> /etc/srp_daemon.conf
	Start_Service srpd
}

__setup_client_mounts_usage()
{
echo -e "Usage:

Setup_Client_Mounts <server> <protocol> <fstype> [backstore <backstore>]
\t[fabrics]
\tserver - name of server (eg. rdma-storage-02)
\tprotocol - iSER or SRP
\tfstype - xfs or ext4 are currently supported
\tbackstore - name of backing device on server, will be prefixed with
\t  either iser- or srp- depending on protocol, if none is given,
\t  will use the default of <protocol>-$host_part
\tfabrics - a list of fabrics to use, if none are give, all available
\t  are used instead"
}

# Call this to set up mount points in fstab for either iSER or SRP targets
Setup_Client_Mounts()
{
	if [ $# -lt 3 ]; then
		echo "Too few arguments, minimum is 3"
		__setup_client_mounts_usage
		return -1
	fi
	local server=$1
	local protocol=$2
	local fstype=$3
	shift 3
	local backstore=$host_part
	case $1 in
	backstore)
		backstore=$2
		shift 2
		;;
	esac
	local fabrics=($*)
	local servers=()
	if [ "${fabrics[1]}" = "all" ]; then
		fabrics=()
	fi
	case $protocol in
	SRP|srp)
		protocol=srp
		servers=(${SRP_SERVERS[*]})
		touch /etc/modprobe.d/ib_srp.conf
		Set_Config_Options /etc/modprobe.d/ib_srp.conf "scale options" "#
		options ib_srp cmd_sg_entries=255 indirect_sg_entries=2048"
		;;
	ISER|iSER|iser)
		protocol=iser
		servers=(${ISER_SERVERS[*]})
		;;
	*)
		echo "Invalid protocol"
		__setup_client_mounts_usage
		;;
	esac
	if ! __if_x_in_y $server "${servers[*]}"; then
		echo "Server not in server list"
		__setup_client_mounts_usage
		return
	fi
	case $fstype in
	xfs)
		mkfs_cmd="/sbin/mkfs.xfs"
		;;
	ext4)
		mkfs_cmd="/sbin/mkfs.ext4"
		;;
	*)
		echo "Unsupported fstype"
		__setup_client_mounts_usage
		return
		;;
	esac
	sd_device_startnum=`ls /dev/sd*[a-z] | wc -w`
	dm_device_startnum=`ls /dev/dm-* | wc -w`
	case $protocol in
	srp)
		Create_Srp_Client_Devices $server $backstore ${fabrics[*]}
		# SRP needs more time for login than iSER
		sleep 10
		;;
	iser)
		Create_Iser_Client_Devices $server $backstore ${fabrics[*]}
		sleep 5
		;;
	esac
	sd_device_endnum=`ls /dev/sd*[a-z] | wc -w`
	if [ $sd_device_startnum -eq $sd_device_endnum ]; then
		echo "No devices added, please make sure the requested connection is supported"
		return
	fi
	dm_device_endnum=`ls /dev/dm-* | wc -w`
	if [ $dm_device_startnum -eq $dm_device_endnum ]; then
		# Only a single scsi device, no dm device
		device=`ls /dev/sd*[a-z] | sort | tail -1`
	else
		# Should only be a single new dm device, and the start num
		# will be the new device's number since we start counting
		# at 0 with dm devices
		device=`echo "/dev/dm-$dm_device_startnum"`
	fi
	$mkfs_cmd $device
	eval `blkid $device | sed -e 'y/ /\n/' | grep -w UUID`
	Set_Config_Options /etc/fstab "mount config for $server $protocol $backstore" "UUID=\"$UUID\"	/srv/$server/$protocol-$backstore	$fstype	defaults,rw,_netdev	1 2"
	echo "New devices added, mount point is:"
	echo -e "\t/srv/$server/$protocol-$backstore"
}

__config_tgtd() {
	name=$1
	block_dev=$2
	share_type=$3
	shift 3
	targetcli /backstores/block create $share_type-$name $block_dev
	case $share_type in
	iser|iSER)
		targetcli /iscsi/${iqn}:$RDMA_HOST/tpg1/luns create storage_object=/backstores/block/$share_type-$name
		;;
	srp|SRP|srpt|SRPt)
		for int in ${SRP_FABRICS[$RDMA_HOST]}; do
			local wwn="ib.${SRP_DGID[$RDMA_HOST-$int]}"
			targetcli /srpt/$wwn/luns create storage_object=/backstores/block/$share_type-$name
		done
		;;
	esac
}

Config_Tgtd() {
	if [ "$OS" = rhel -a "$RELEASE" -lt 7 ]; then
		return 1
	fi
	if [ "$OS" = fedora -a "$RELEASE" -lt 18 ]; then
		return 1
	fi
	__config_tgtd $*
	targetcli saveconfig
}

Enable_Tgtd() {
	local srpt_conf=/etc/modprobe.d/ib_srpt.conf
	# rhel6 uses scsi-target-utils, rhel5 and earlier just don't work
	# Fedora for 18 or later and rhel7 use the LIO kernel target,
	# configured by targetcli
	if [ "$OS" = rhel -a "$RELEASE" -lt 7 ]; then
		return 1
	fi
	if [ "$OS" = fedora -a "$RELEASE" -lt 18 ]; then
		return 1
	fi
	$INSTALL targetcli
	touch $srpt_conf
	Set_Config_Options $srpt_conf "max request tuning" "options ib_srpt srp_max_req_size=8296"
	targetcli set global auto_save_on_exit=false
	targetcli set global auto_add_mapped_luns=false
	Enable_Service target
	targetcli clearconfig confirm=True
	shopt -s nullglob
	# Create our global iSER device
	targetcli /iscsi create ${iqn}:$RDMA_HOST
	targetcli /iscsi/${iqn}:$RDMA_HOST/tpg1/portals/0.0.0.0:3260 enable_iser true
	# Create our target SRP wwns
	for int in ${SRP_FABRICS[$RDMA_HOST]}; do
		targetcli /srpt create ${SRP_DGID[$RDMA_HOST-$int]}
		targetcli /srpt/ib.${SRP_DGID[$RDMA_HOST-$int]} set attribute srp_sq_size=8192
	done
	shopt -u nullglob
	targetcli saveconfig
	sed -e 's/^SRPT_LOAD=.*/SRPT_LOAD=yes/g' -i $RDMA_CONFIG
	sed -e 's/^ISERT_LOAD=.*/ISERT_LOAD=yes/g' -i $RDMA_CONFIG
	Create_Target_Restart_Dispatcher
}

__disable_repo() {
	[ -f /etc/yum.repos.d/$1.repo ] && \
		sed -e 's/enabled=1/enabled=0/' -i /etc/yum.repos.d/$1.repo
}

__enable_repo() {
	[ -f /etc/yum.repos.d/$1.repo ] && \
		sed -e 's/enabled=0/enabled=1/' -i /etc/yum.repos.d/$1.repo
}

__install_additional_repos() {
	if [ $OS = "rhel" -a $RELEASE -gt 5 ]; then
		cat << EOF > /etc/yum.repos.d/rhpkg.repo
[rhpkg]
name=rhpkg for $OS ${RELEASE}
baseurl=http://beaker.ofa.iol.unh.edu/$OS/\$releasever/
enabled=0
skip_if_unavailable=1
gpgcheck=0
EOF
	fi
	if [ $OS = "rhel" -a $RELEASE -lt 8 ]; then
		cat << EOF > /etc/yum.repos.d/epel.repo
[epel]
name=Extra Packages for Enterprise Linux $RELEASE - \$basearach
baseurl=http://download.fedoraproject.org/pub/epel/$RELEASE/\$basearch
#mirrorlist=https://mirrors.fedoraproject.org/metalink?repo=epel-${RELEASE}&arch=\$basearch
failovermethod=priority
enabled=1
skip_if_unavailable=1
gpgcheck=0
EOF
	fi
}

Install_Packages() {
	# XXX: We have to jump through hoops here.  The update to dnf in
	# the latest fedora changed how yum/dnf works in regards to
	# broken packages.  Namely, --skip-broken is now the default, but
	# it isn't identical to the old version in yum in that in yum
	# if you list 10 packages on an install command, and you include
	# --skip-broken, and it only find matches for 7 of the 10 packages
	# you listed, then it installs those 7 and skips the 3 that weren't
	# found.  The new dnf no longer has --skip-broken, it is supposed
	# to be the default behavior, but if you list packages on the
	# command line that aren't found, then it aborts the entire
	# transaction.  This is a pain in the butt for us because we run
	# this script on Fedora and RHEL and from releases both old and
	# new, and the same set of packages do not exist in all these
	# different versions.  So, now, for any package that might not
	# exist in some of the versions, we have run it in a command by
	# itself or risk having it cause other packages not to get
	# installed.

	# If we are rhel5 or earlier, OFED specific packages
	if [ $OS = "rhel" -a $RELEASE -lt 6 ]; then
		$INSTALL openib "ofed*" "openib-*" "libsdp*"
	else
		$INSTALL rdma mstflint
	fi
	# the very core packages available on all release
	$INSTALL pciutils nfs-utils libibverbs libibverbs-utils libibverbs-devel librdmacm librdmacm-utils librdmacm-devel libibcm libmthca libmlx4 libipathverbs libcxgb3 openmpi openmpi-devel qperf perftest infiniband-diags ibutils iscsi-initiator-utils rpmdevtools

	# packages we need to do one at a time in case they don't exist
	# somewhere
	if [ "$SPLIT_INSTALLS" = "yes" ]; then
		$INSTALL libcxgb4
		$INSTALL libmlx5
		$INSTALL libocrdma
		$INSTALL libusnic_verbs
		$INSTALL srptools
		$INSTALL rds-tools
		$INSTALL ibacm-devel
		$INSTALL opa-basic-tools opa-ff opa-fastfabric opa-address-resolution
		$INSTALL dapl-utils compat-dapl-utils mvapich-devel mvapich2-devel mpitests
	else
		$INSTALL libcxgb4 libmlx5 libocrdma libusnic_verbs srptools rds-tools ibacm-devel dapl-utils compat-dapl-utils mvapich-devel mvapich2-devel mpitests
	fi
	if [ -f /etc/srp_daemon.conf ]; then
		echo "d" >> /etc/srp_daemon.conf
	fi
	# The new hfi1 stuff and the old qib stuff can't coexist on the same
	# system due to soname conflicts between infinipath-psm and libpsm2
	# Only install the qib stuff if we have a qib card, otherwise install
	# the opa stuff
	QIB=`lspci | grep "InfiniBand: QLogic Corp. IBA"`
	if [ -z "$QIB" ]; then
		$INSTALL infinipath-psm openmpi-psm-devel mvapich-psm-devel mvapich2-psm-devel
	else
		$INSTALL libhfi1 opa-ff opa-fm opa-address-resolution opa-basic-tools libpsm2
	fi

	# Try to get git before installing the epel repo as that sometimes
	# breaks git checkouts
	$INSTALL "git*" strace ltrace oprofile systemtap diffstat xorg-x11-xauth psmisc bash-completion grubby

	if [ -d /etc/rdma ]; then
		RDMA_PATH=/etc/rdma
		RDMA_CONFIG=/etc/rdma/rdma.conf
	else
		RDMA_PATH=/etc/ofed
		RDMA_CONFIG=/etc/ofed/openib.conf
	fi

	__install_additional_repos

	# Install a few other things that it would be nice to have,
	# probably come from different repos depending on release,
	# and that we don't want a failure to get these items to screw
	# up the install
	$INSTALL "scsi-target*"
	$INSTALL "tgtd*"
	$INSTALL vconfig
	[ $OS = "rhel" -a $RELEASE -eq 6 ] && \
		(get_file pkg_overrides/rhel/6/noarch/python-decoratortools-1.7-4.1.el6.noarch.rpm
		 $INSTALL ./python-decoratortools-1.7-4.1.el6.noarch.rpm)
	$INSTALL "fedpkg*"
	[ $OS = "rhel" -a $RELEASE -lt 7 ] && \
		($INSTALL "git*"
		 $INSTALL bash-completion)

	# Most of these are in Fedora/EPEL, but not in RHEL.  Install them
	# before we disable EPEL.  For pre-release RHEL products, we will
	# likely need manual overrides until EPEL exists for that release
	if [ "$SPLIT_INSTALLS" = "yes" ]; then
		for i in iperf iperf3 uperf sockperf nuttcp netperf atop ftop htop iftop iotop latencytop-tui ntop numatop tiptop bonnie++ dbench tiotest device-mapper-multipath; do
			$INSTALL $i
		done
	else
		$INSTALL iperf iperf3 uperf sockperf nuttcp netperf atop ftop htop iftop iotop latencytop-tui ntop numatop tiptop bonnie++ dbench tiotest device-mapper-multipath
	fi

	# Assuming we got git, and we have bash-completion,
	# try to link the bash completion for git_ps1
	[ -d /etc/bash_completion.d -a -f /usr/share/git-core/contrib/completion/git-prompt.sh ] && ln -sf ../../usr/share/git-core/contrib/completion/git-prompt.sh /etc/bash_completion.d/

	__enable_repo rhpkg
	[ $OS = "rhel" -a $RELEASE -lt 6 ] || \
		$INSTALL rhpkg
	[ $OS = "rhel" -a $RELEASE -lt 6 ] && \
		$INSTALL rhpkg-simple
	__disable_repo rhpkg

	$INSTALL brew brewkoji

	# OpenSM should not be installed at this point, but just in case it
	# is, disable it
	Disable_Service opensm
	Disable_Service opensmd
	#turn on rdma/openibd
	Enable_Service openib
	Enable_Service openibd
	Enable_Service rdma
	Disable_Service ibacm
	if [ $OS = rhel -a $RELEASE -lt 7 ]; then
		Enable_Service network
		Disable_Service NetworkManager
	else
		Disable_Service network
		Enable_Service NetworkManager
		$INSTALL NetworkManager-tui
	fi
	Disable_Service cpuspeed
	sed -e 's/SRP_LOAD=no/SRP_LOAD=yes/;s/ISER_LOAD=no/ISER_LOAD=yes/;s/RDS_LOAD=yes/RDS_LOAD=no/;s/LOAD_RDS.*/RDS_LOAD=no/;s/TECH_PREVIEW_LOAD.*/TECH_PREVIEW_LOAD=yes/' -i $RDMA_CONFIG

	# Disable the various firewalls as they aren't set up by default for
	# our use case
	Disable_Service firewalld
	Disable_Service iptables
	Disable_Service ip6tables
}

Install_Virt_Packages() {
	$INSTALL "libvirt*" "qemu*" "virt*" "libguestfs*" "cyrus*"
	Enable_Service libvirtd
        local status=$(mktemp)
	virsh vol-list --pool default > $status 2>&1
	grep "failed to connect" $status >/dev/null 2>&1
	libv_running=$?
	rm -f $status
	# Enable remote control of virtual machines
	sed -e 's/#listen_tls = .*/listen_tls = 0/;s/#listen_tcp = .*/listen_tcp = 1/;s/#auth_tcp = .*/auth_tcp = "sasl"/;s/#keepalive_count = .*/keepalive_count = 50/' -i /etc/libvirt/libvirtd.conf
	sed -e 's/#LIBVIRTD_ARGS="--listen"/LIBVIRTD_ARGS="--listen"/' -i /etc/sysconfig/libvirtd
	saslpasswd2 -d -a libvirt rdma-virt
	echo "rdma-virt-passwd" | saslpasswd2 -c -p -a libvirt rdma-virt
	[ $libv_running -eq 1 ] && Restart_Service libvirtd
}

Clear_Virt_Default_Network() {
	if [ $libv_running -eq 1 ]; then
		# In case libvirt is running, issue these commands
		virsh net-destroy Default
		virsh net-undefine Default
		virsh net-destroy default
		virsh net-undefine default
	else
		# But this is what will do the trick during %post
		rm -f /etc/libvirt/qemu/networks/autostart/Default.xml
		rm -f /etc/libvirt/qemu/networks/Default.xml
		rm -f /etc/libvirt/qemu/networks/autostart/default.xml
		rm -f /etc/libvirt/qemu/networks/default.xml
	fi
}

Copy_Virt_Domains() {
	pushd /root >/dev/null
	mkdir -p libvirt/images
	pushd libvirt >/dev/null
	rm -f *.xml
	get_dir libvirt/$RDMA_HOST/ .xml
	# libvirtd isn't running, safe to remove domains the easy way
	[ $libv_running -eq 0 ] && rm -f /etc/libvirt/qemu/{autostart/*,*.xml}
	[ $libv_running -eq 1 ] && for i in *.xml; do
			virsh destroy `basename $i .xml`
			virsh undefine `basename $i .xml`
		done
	pushd images >/dev/null
	rm -f *.xml
	get_dir libvirt/$RDMA_HOST/images/ .xml
	# libvirtd isn't running, safe to remove image files the easy way
	[ $libv_running -eq 0 ] && rm -f /var/lib/libvirt/images/*
	[ $libv_running -eq 1 ] && for i in *.xml; do
			virsh vol-delete --pool default `basename $i .xml`.qcow2
			virsh vol-create --pool default --file $i
		done
	popd >/dev/null
	[ $libv_running -eq 1 ] && for i in *.xml; do
			virsh define $i
		done
	[ $libv_running -eq 0 ] && sed -e '/Start one time virt setup script/,/End one time virt setup script/d' -i /etc/rc.d/rc.local
	[ $libv_running -eq 0 ] && cat >> /etc/rc.d/rc.local <<EOF
# Start one time virt setup script
libv_running=0
passes=0
while [ \$libv_running -eq 0 ]; do
	virsh vol-list --pool default > .tmp.status 2>&1
	grep "failed to connect" .tmp.status >/dev/null 2>&1
	libv_running=\$?
	rm -f .tmp.status
	[ \$passes -eq 0 ] && let passes++ || ( let passes++; sleep 1 )
	[ \$passes -gt 20 ] && exit 1
done

pushd /root/libvirt >/dev/null
pushd images >/dev/null
for i in *.xml; do
	virsh vol-create --pool default --file \$i
done
popd >/dev/null
for i in *.xml; do
	virsh define \$i
done
popd >/dev/null
sed -e '/Start one time virt setup script/,/End one time virt setup script/d' -i /etc/rc.d/rc.local
# End one time virt setup script
EOF
	chmod +x /etc/rc.d/rc.local
	popd >/dev/null
	popd >/dev/null
}

Install_Override_Packages() {
	rm -fr pkg_override
	mkdir pkg_override
	pushd pkg_override >/dev/null
	get_dir pkg_overrides/$OS/$RELEASE/`uname -p`/ .rpm
	get_dir pkg_overrides/$OS/$RELEASE/noarch/ .rpm
	shopt -s nullglob
	if [ -n "./*" ]; then
		$INSTALL ./*
	fi
	shopt -u nullglob
	popd >/dev/null
}

Enable_IP_Forwarding() {
	cur=`grep ip_forward /etc/sysctl.conf`
	if [ -n "$cur" ]; then
		sed -e 's/net\.ipv4\.ip_forward.*=.*0/net\.ipv4\.ip_forward = 1/' -i /etc/sysctl.conf
	else
		echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/ip_forward
	fi
}

Setup_Opensm() {
	# Install the opensm program
	$INSTALL opensm
	# turn opensm on rdmamaster only.
	Enable_Service opensm
	Enable_Service opensmd
	get_file opensm.conf-$RDMA_HOST
	mv opensm.conf{-$RDMA_HOST,}
	get_file partitions.conf
	rm -f $RDMA_PATH/opensm.conf*
	rm -f $RDMA_PATH/partitions*.conf
	mv opensm.conf $RDMA_PATH
	mv partitions.conf $RDMA_PATH
	mkdir -p /var/log/opensm/ib1
}

Setup_Opafm() {
	$INSTALL opa-fm
	$INSTALL opa-fmgui
	Enable_Service opafm
}

__generate_dhcpd_base() {
	out=dhcpd.conf.base
	cat > $out << EOF
#
# DHCP Server Configuration file.
#   see /usr/share/doc/dhcp*/dhcpd.conf.sample
#   see 'man 5 dhcpd.conf'
#
#
# This file is autogenerated by the rdma-functions.sh script
# Do not manually edit and expect your changes to survive the
# next install cycle.
#

ignore client-updates;

EOF
	for subnet in ${all_nets[*]}; do
		__get_net_from_subnet $subnet
		echo "# subnet $subnet" >> $out
		echo "subnet ${network_prefix}.$net.0 netmask 255.255.255.0 {" >> $out
		echo "	authoritative;" >> $out
		echo "" >> $out
		echo "	# option routers ${network_prefix}.$net.254;" >> $out
		echo "	option subnet-mask 255.255.255.0;" >> $out
		echo "	range ${network_prefix}.$net.240 ${network_prefix}.$net.251;" >> $out
		[ -n ${domain_name+x} ] && echo "	option domain-name \"${domain_name}\";" >> $out
		if [ -n ${domain_name_servers[0]+x} ]; then 
			local ns_string="${domain_name_servers[*]}"
			echo "	option domain-name-servers ${ns_string//${IFS:0:1}/,};" >> $out
		fi
		echo "	# option time-offset	-18000; #EST" >> $out
		echo "	default-lease-time	3600; #1 hour so we see problems faster" >> $out
		echo "	max-lease-time		7200;" >> $out
		echo "	# filename		\"pxelinux.0\";" >> $out
		echo "}" >> $out
		echo "" >> $out
	done
}

Setup_Dhcp_Server() {
	if [ "$RDMA_HOST" != "builder-00" ]; then
		echo "The Setup_Dhcp_Server function can only be used on the"
		echo "host builder-00."
		return
	fi
	# We need to create an iptables setup that blocks all dhcp traffic on
	# the lab network interface
	#
	# FSDP lab is running firewalld on all non-test-nodes, removing this.
# 	eth0=lom_1
# 	eth=lom_+
# 	cat << EOF > /etc/sysconfig/iptables
# # Manually created firewall rules, do not run any firewall rules editing
# # programs or these rules will be lost

# # We must take special care to make sure that the dhcp server we will be
# # running won't attempt to respond to anything on the test lab network
# *filter
# :INPUT ACCEPT [0:0]
# :FORWARD ACCEPT [0:0]
# :OUTPUT ACCEPT [0:0]
# -A OUTPUT -p tcp -m tcp --sport bootps -o $eth0 -j REJECT
# -A OUTPUT -p udp -m udp --sport bootps -o $eth0 -j REJECT
# COMMIT
# EOF
# 	Enable_Service iptables
# 	Disable_Service ip6tables
# 	Disable_Service firewalld

	# Get our dhcpd.conf file and turn on dhcpd
	$INSTALL dhcp
	pushd /etc/dhcp >/dev/null
	__generate_dhcpd_base
	get_file gen_dhcpd_conf
	chmod +x gen_dhcpd_conf
	if [ ! -d hosts.d ]; then
		mkdir hosts.d
	fi
	./gen_dhcpd_conf
	popd >/dev/null
	Enable_Service dhcpd
}

Create_Client_Ids() {
	# Usage: pass the 8byte GUID(s), spits out RFC4390, RFC4361, RFC4122,
	# and RFC6355 client IDs and also spits out an InfiniBand hardware
	# address encoded as a client ID (whew!)
	# guid format: 8 bytes in colon hex format, aka 00:01:02:03:04:05:06:07
local __awk_src='
BEGIN {
	if (id != "") {
		machine_id=substr(id, 1, 2)
		for (i=3; i<=31; i+=2)
			machine_id=machine_id":"substr(id, i, 2)
	}
}
{
	if (NF != 8) {
		print "Wrong number of elements in GID: "NF
		print "Line was: "$0
		exit 1
	}
	# Custom Mellanox as used by everything up to rhel7/f20
	print "ff:00:00:00:00:00:02:00:00:02:c9:00:"$1":"$2":"$3":"$4":"$5":"$6":"$7":"$8
	# RFC4361 as used by f21 through f23 cant be worked out until after
	#  the machine has asked for a dhcp address for the first time as
	#  the variable part is non-predictable
	# RFC4122 as used by f24 and later uses the machine id of the system
	#  and we have access to that, so we can figure it out
	if (machine_id)
		print "ff:"$5":"$6":"$7":"$8":00:04:"machine_id
	# Encode this GID as a hardware address wrapped in a client-id
	print "20:"$1":"$2":"$3":"$4":"$5":"$6":"$7":"$8
}'
	ID=()
	local machine_id=""
	[ -f /etc/machine-id ] && machine_id=`cat /etc/machine-id`
	for gid in $*; do
		local temp_id
		temp_id=$(echo $gid | awk -F ':' -v id="$machine_id" -- "$__awk_src")
		ID=(${ID[*]} $temp_id)
	done
}

Setup_Dhcp_Client() {
	[ "$RDMA_HOST" = "rdma-master" -o "$RDMA_HOST" = "rdma-storage-01" ] && return
	rm -f /root/$RDMA_HOST.dhcp.?
	ssh rdma-master "rm -f /etc/dhcp/hosts.d/$RDMA_HOST.dhcp.*"
	ssh rdma-storage-01 "rm -f /etc/dhcp/hosts.d/$RDMA_HOST.dhcp.*"
	[ -z "${IPS[*]}" ] && return
	macs=0
	eths=0
	for mac in ${HARDWARE[*]}; do
		let eths++
		let macs++
	done
	gids=0
	for gid in ${GIDS[*]}; do
		let gids++
		let macs++
	done
	Create_Client_Ids ${GIDS[*]}
	ids=0
	for id in ${ID[*]}; do
		let ids++
	done
	k=0
	while [ $k -lt $macs -o $k -lt $ids ]; do
		echo -ne "host $RDMA_HOST.$k {\n" > $RDMA_HOST.dhcp.$k
		echo -ne "\tfixed-address " >> $RDMA_HOST.dhcp.$k
		j=0
		for i in ${IPS[*]}; do
			[ $j -gt 0 ] && echo -ne "," >> $RDMA_HOST.dhcp.$k
			echo -ne "$i" >> $RDMA_HOST.dhcp.$k
			let j++
		done
		echo -ne ";\n" >> $RDMA_HOST.dhcp.$k
		if [ $k -lt $eths ]; then
			echo -ne "\thardware ethernet ${HARDWARE[$k]};\n" >> $RDMA_HOST.dhcp.$k
		elif [ $(($k - $eths)) -lt $gids ]; then
			echo -ne "\thardware infiniband ${GIDS[$(($k - $eths))]};\n" >> $RDMA_HOST.dhcp.$k
		fi
		[ -n "${ID[$k]}" ] && \
			echo -ne "\toption dhcp-client-identifier=${ID[$k]};\n" >> $RDMA_HOST.dhcp.$k
		echo -ne "}\n\n" >> $RDMA_HOST.dhcp.$k
		let k++
	done
	scp $RDMA_HOST.dhcp.? rdma-master:/etc/dhcp/hosts.d
	scp $RDMA_HOST.dhcp.? rdma-storage-01:/etc/dhcp/hosts.d
	ssh rdma-master /etc/dhcp/gen_dhcpd_conf
	ssh rdma-storage-01 /etc/dhcp/gen_dhcpd_conf
}

Unlimit_Resources() {
	if [ -d /etc/security/limits.d ]; then
		cat << EOF > /etc/security/limits.d/rdma.conf
# configuration for rdma performance tuning
*	soft	memlock		unlimited
*	hard	memlock		unlimited
*	soft	stack		unlimited
*	hard	stack		unlimited
*	soft	core		unlimited
*	hard	core		unlimited
# rdma tuning end
EOF
	else
		Set_Config_Options /etc/security/limits.conf "rdma tuning" "*	soft	memlock		unlimited
*	hard	memlock		unlimited
*	soft	stack		unlimited
*	hard	stack		unlimited
*	soft	core		unlimited
*	hard	core		unlimited"
	fi
}

Usability_Enhancements() {
	$INSTALL tree vim-enhanced vim-X11 screen bind-utils
	get_file vimsetup.tgz
	tar xf vimsetup.tgz
	get_file bashrc
	mv bashrc .bashrc
	if [ "$ARCH_FAMILY" = "x86" -a -d /boot/efi -a -x /usr/sbin/efibootmgr ]; then
		cat << EOF >>/root/.bashrc
alias shutdown=rhts-reboot
EOF
	fi
	get_file dir_colors
	mv dir_colors .dir_colors
	DRP=/etc/kernel/postinst.d/51-dracut-rescue-postinst.sh
	[ -f $DRP ] && mv $DRP{,~}
	Set_Config_Options /root/.bash_profile "ps1 options" "export GIT_PS1_SHOWDIRTYSTATE=yes
export PS1='[\u@\h \W\$(__git_ps1 \" (%s)\")]\$ '"
}

Setup_Test_User_Ssh() {
	#honli, Oct 11, 2012
	# setup passwordless ssh configuration for non-root user 'test',
	# then we can run openmpi benchmark by non-root user
	rm -fr /home/test/.ssh
	cp -r /root/.ssh /home/test
	chown -R test:test /home/test
}

Get_MACs_Of_Host() {
	ETHER_MACS=`ip link show | awk '/.*ether.*/{ print $2 }' | sort | uniq`
	IB_MACS=`ip link show | awk '/.*infiniband.*/{ print $2 }' | sort | uniq`
	MACS=( $ETHER_MACS $IB_MACS )
}

__set_hostname_via_sysconfig() {
	sed -e 's/HOSTNAME=.*$/HOSTNAME='${RDMA_HOST}'\.ofa\.iol\.unh\.edu/' -i /etc/sysconfig/network
}

Set_Hostpart() {
	[ -z "$RDMA_HOST" ] && return
	if [ $RDMA_HOST != rdma-master ]; then
		host_part=`echo $RDMA_HOST | cut -f 2- -d '-'`
	else
		host_part=$RDMA_HOST
	fi
}

Enable_Fips_Mode() {
	[ "$OS" = rhel -a "$RELEASE" -lt 6 ] && return
	[ "$OS" = fedora -a "$RELEASE" -lt 18 ] && return
	if [ -f /etc/sysconfig/prelink ]; then
		sed -e 's/PRELINKING=.*/PRELINKING=no/g' -i /etc/sysconfig/prelink
		prelink -au
	fi
	$INSTALL dracut-fips
	BOOT=`df | grep boot | awk '{print $1}'`
	[ -n "$BOOT" ] && BOOT="boot=$BOOT fips=1" || BOOT="fips=1"
	[ -f /boot/grub/grub.conf ] && sed -e '/.*fips=1.*/n; s#.*kernel /vmlinuz-.*#& '"${BOOT}"'#' -i /boot/grub/grub.conf
	[ -f /etc/default/grub ] && (. /etc/default/grub; sed -e '/.*fips=1.*/n; s#GRUB_CMDLINE_LINUX=".*"#GRUB_CMDLINE_LINUX="'"$GRUB_CMDLINE_LINUX ${BOOT}"'"#' -i /etc/default/grub) && grub2-mkconfig -o /boot/grub2/grub.cfg
	dracut -f -v

}
