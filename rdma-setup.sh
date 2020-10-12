#!/bin/bash

LOOKASIDE="http://beaker.ofa.iol.unh.edu/fsdp_setup"
COPY_INSTEAD=false

get_file() {
	rm -f `basename "$1"`
	if [ "$COPY_INSTEAD" = "true" ]; then
		cp "${LOOKASIDE}/$1" ./
	else
		wget -q "${LOOKASIDE}/$1"
	fi
}

get_dir() {
	EXT=""
	if [ "$COPY_INSTEAD" = "true" ]; then
		[ -n "$2" ] && EXT="*$2"
		cp -af "${LOOKASIDE}/${1}"${EXT} ./
	else
		[ -n $2 ] && EXT="-A$2"
		wget -qr -l1 -np -nd -nH $EXT "${LOOKASIDE}/$1"
	fi
}

# WARNING: You must test for fedora-release first here as some releases of
# fedora have a symlink from redhat-release to fedora-release that will
# confuse this test.  But no version of rhel ever had a fedora-release file
# so we are safe knowing that if fedora-release exists, then it's fedora.
if [ -f /etc/fedora-release ]; then
	OS=fedora
	RELEASE=`cat /etc/fedora-release | grep release | cut -f 3 -d ' '`
else
	OS=rhel
	RELEASE=`cat /etc/redhat-release | grep release | grep -o '[0-9]*\.[0-9]' | cut -f 1 -d '.'`
fi
ARCH=`uname -i`
case $ARCH in
	ppc64|ppc64le)
		ARCH_FAMILY=ppc
		;;
	i386|i686|x86_64)
		ARCH_FAMILY=x86
		;;
	s390|s390x)
		ARCH_FAMILY=s390
		;;
	aarch64)
		ARCH_FAMILY=aarch64
		;;
esac

# If the OS uses dnf, set the package $INSTALL command to use dnf;
# otherwise continue to use yum
if [ -x /usr/bin/dnf ]; then
	dnf -y -q makecache
	SPLIT_INSTALLS=yes
	INSTALL="dnf -y -q --allowerasing --setopt=strict=0 install"
else
	yum -y -q makecache
	SPLIT_INSTALLS=no
	INSTALL="yum -y -q --skip-broken install"
fi

# Parse all command line options
while [ -n "$1" ]; do
	case $1 in
	--skip-rpms)
		# When running from the command line, it's often nice to
		# skip all of the install work since that's what takes
		# the longest
		SPLIT_INSTALLS=no
		INSTALL="echo yum -y -q --skip-broken install"
		shift 1
		;;
	--src)
		# Don't get files from a server, get them from a local
		# source instead
		COPY_INSTEAD=true
		LOOKASIDE="$2"
		shift 2
		;;
	*)
		# Don't get into an infinite loop because of bad options
		shift 1
		;;
	esac
done

[ -x /usr/bin/wget -a "$COPY_INSTEAD" != "true" ] || $INSTALL wget

echo -n "Installing for "
[ $OS = "rhel" ] && echo "${OS}${RELEASE}" || echo "${OS} ${RELEASE}"

cd /root
get_file rdma-functions.sh
. ./rdma-functions.sh

# Common things to be done on all hosts
Update_Etc_Hosts
Install_Packages
Unlimit_Resources
Usability_Enhancements
Setup_FSDP_Mounts

# This will set ETHER_MACS, IB_MACS, and MACS[] and must be done even if
# we know our hostname
Get_MACs_Of_Host
host_config_done=""

RDMA_HOST=`hostname -s`
if [ -n "$RDMA_HOST" -a "$RDMA_HOST" != "localhost" ]; then
	get_file machines/"$RDMA_HOST"
	if [ -f "$RDMA_HOST" ]; then
		. ./"$RDMA_HOST"
		host_config_done="yes"
	fi
fi
if [ -n "$host_config_done" ]; then
	RDMA_HOST=`echo $HOSTNAME | cut -f 1 -d '.'`
	if [ -z "$RDMA_HOST" -a "$RDMA_HOST" != "localhost" ]; then
		get_file machines/"$RDMA_HOST"
		if [ -f "$RDMA_HOST" ]; then
			. ./"$RDMA_HOST"
			host_config_done="yes"
		fi
	fi
fi
if [ -z "$host_config_done" ]; then
	for mac in ${MACS[*]}; do
		echo "Trying to retrieve $mac..."
		get_file machines/"$mac"
		if [ -f "$mac" ]; then
			. ./"$mac"
			host_config_done="yes"
			break
		fi
	done
fi
if [ -z "$host_config_done" ]; then
	echo "Error!  Unable to find a host configuration for this machine!"
	echo
	echo "Tried:"
	echo "	hostname -s:	`hostname -s`"
	echo "	HOSTNAME:	$HOSTNAME"
	echo "	MACs:		${MACS[*]}"
	echo
	echo "Setup is incomplete."
else
	Set_Config_Options /root/.bash_profile "setup options" "export RDMA_HOST=$RDMA_HOST
export host_part=$host_part
export HOST_FABRICS=(${HOST_FABRICS[*]})
export OS=$OS
export RELEASE=$RELEASE
cp -f rdma-functions.sh rdma-functions.sh~
get_file rdma-functions.sh
[ ! -f rdma-functions.sh ] && cp rdma-functions.sh~ rdma-functions.sh
. ~/rdma-functions.sh"

	# These commands need ${HOST} to be set, so must come after we
	# source our interface definition file
	# ssh configuration for non-root user 'test'. honli
	Setup_Test_User_Ssh

	# During the host specific config, we should have added our various
	# mac addresses to the list DHCP_MACS and DHCP_CLIENT_IDS, but
	# we can't ssh to rdma-master and create our hosts.d/host file
	# until after the Setup_SSH routine is done, so we do it now.
	Setup_Dhcp_Client
fi

# Do this last as we might need host specific information
Fix_Boot_Loader

# Do this even laster than the above step as it will fiddle with grub
#Enable_Fips_Mode

restorecon -R /root /etc /boot /lib /home/test

# Always rebuild the initrd in case we changed module options
# or enabled FIPS mode
if [ "$OS" = "rhel" -a "$RELEASE" -le 5 ]; then
	mkinitrd -f
else
	dracut -f
fi
