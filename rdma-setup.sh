#!/bin/bash
TOPDIR=/root/fsdp_setup

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
	SPLIT_INSTALLS=yes
	INSTALL="dnf -y -q --allowerasing --setopt=strict=0 install"
else
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
	*)
		# Don't get into an infinite loop because of bad options
		shift 1
		;;
	esac
done

echo -n "Installing for "
[ $OS = "rhel" ] && echo "${OS}${RELEASE}" || echo "${OS} ${RELEASE}"

pushd "${TOPDIR}"
source rdma-functions.sh

# Common things to be done on all hosts
Update_Etc_Hosts
Unlimit_Resources
Install_Packages
Usability_Enhancements
Setup_FSDP_Mounts

# This will set ETHER_MACS, IB_MACS, and MACS[] and must be done even if
# we know our hostname
Get_MACs_Of_Host
host_config_done=""

RDMA_HOST=`hostname -s`
if [ -n "$RDMA_HOST" -a "$RDMA_HOST" != "localhost" ]; then
	if [ -f "machines/$RDMA_HOST" ]; then
		source machines/"$RDMA_HOST"
		host_config_done="yes"
	fi
fi
if [ -z "$host_config_done" ]; then
	echo "Error!  Unable to find a host configuration for this machine!"
	echo "Setup is incomplete."
else
	Set_Config_Options /root/.bash_profile "setup options" "export RDMA_HOST=$RDMA_HOST
export HOST_FABRICS=(${HOST_FABRICS[*]})
export OS=$OS
export RELEASE=$RELEASE
source ~/fsdp_setup/rdma-functions.sh"

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

restorecon -R /root /etc /boot /lib
