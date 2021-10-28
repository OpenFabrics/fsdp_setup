# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi

if [ "$TERM" = "vt102" ]; then
	export TERM=vte-256color
	eval `dircolors -b .dir_colors`
	alias ls="ls --color=auto"
fi

alias grep='/bin/grep --color=tty '
alias vi=vim
export EDITOR=vim

RDMA_LOOKASIDE="http://beaker.ofa.iol.unh.edu/fsdp_setup"
get_file() {
	rm -f `basename "$1"`
	wget -q "${RDMA_LOOKASIDE}/$1"
}
get_dir() {
	EXT=""
	[ -n $2 ] && EXT="-A$2"
	wget -qr -l1 -np -nd -nH $EXT "${RDMA_LOOKASIDE}/$1"
}

__show_link_state='
BEGIN {
	printf "%s:", dev;
	if (length(dev) < 23) printf "\t";
	if (length(dev) < 15) printf "\t";
	if (length(dev) < 7) printf "\t";
}
/NO-CARRIER/ && /[\<,]UP[\>,]/ { printf "No Link, Interface UP\t" };
/LOWER_UP/ && /[\<,]UP[\>,]/ { printf "Link UP, Interface UP\t" };
/NO-CARRIER/ && !/[\<,]UP[\>,]/ { printf "No Link, Interface Down\t" };
/LOWER_UP/ && !/[\<,]UP[\>,]/ { printf "Link UP, Interface Down\t" };
!/LOWER_UP|NO-CARRIER/ { printf "%s\tInterface off\t", $2 };
'

__show_ip_addr='
BEGIN { once = 0 }
/ inet / { if (once == 0) { once = 1; printf "%s", $2 }
	   else printf ", %s", $2 }
END { printf "\n" }
'

_show_ib_dev_state() {
	ip -o link show $1 | awk -v dev=$1 "$__show_link_state"
                ip addr show $1 | awk "$__show_ip_addr"
}

_ib_dev() {
	for i in `ip -o link show | grep -w ".*_$1:" | grep -v "$1@" | awk -F ': ' '{ print $2 }' | cut -f 1 -d '@'`; do
                [ -n "$i" ] && _show_ib_dev_state $i
        done
}

ib() {
	for dev in ib0 ib0.800{2,4,6} ib0_1 ib0_1.800{2,4,6} ib0_2 ib0_2.800{2,4,6} ib0_3 ib0_3.800{2,4,6} ib0_4 ib0_4.800{2,4,6}; do
		_ib_dev $dev
        done
}

opa() {
	for dev in opa0 opa0.8022; do
		_ib_dev $dev
        done
}

_show_en_dev_state() {
	ip -o link show $1 | head -n 1 | awk -v dev=$1 "$__show_link_state"
	ip addr show $1 | awk "$__show_ip_addr"
	if [ `ip -o link show $1 | tail -n +2 | wc -l` -gt 0 ]; then
		ip -o link show $1 | tail -n +2
	fi
}

en() {
	for dev in lab-bridge0 lom_1; do
		i=`ip -o link show $dev | awk -F ': ' '{ print $2 }'`
		[ -n "$i" ] && _show_en_dev_state $i && break
	done
        for dev in roce roce.43 roce.45 roce.{50..52} roce_1 roce_1.4{3,5} roce_2 roce_2.4{3,5} roce_3 roce_3.4{3,5} roce_4 roce_4.4{3,5} iw iw.51 iw.52 ; do
		i=`ip -o link show | grep -w ".*$dev" | grep -v master | grep -v "@.*$dev" | awk -F ': ' '{ print $2 }'`
                i=`echo $i | cut -f 1 -d '@'`
		[ -n "$i" ] && _show_en_dev_state $i
        done
	for dev in slave1 slave2 slave3 slave4; do
		i=`ip -o link show | grep -w ".*$dev" | grep -v "@.*$dev" | awk -F ': ' '{ print $2 }'`
                i=`echo $i | cut -f 1 -d '@'`
		[ -n "$i" ] && _show_en_dev_state $i
        done
}

clean_kernels() {
	VERSIONS=`rpm -q --queryformat="%{version}-%{release}.%{arch}\n" kernel | sort -V --reverse`
	RUNNING_VER=`uname -r`
	# We want to leave these kernels:
	# 1) The running kernel
	# 2) The most recent RPM kernel
	# 3) The most recent devel kernel (if any installed)
	# 4) One backup RPM kernel
	rpm_running=0
	latest_rpm_ver=""
	backup_rpm_ver=""
	latest_devel_ver=""
	i=0
	for ver in $VERSIONS; do
		let i++
		[ $ver = $RUNNING_VER ] && rpm_running=$i
	done
	i=0
	for ver in $VERSIONS; do
		let i++
		if [ $i -eq 1 ]; then
			echo "Keeping latest RPM kernel $ver"
			latest_rpm_ver=$ver
		elif [ $i -eq 2 -a $rpm_running -le 1 ]; then
			echo "Keeping backup RPM kernel $ver"
			backup_rpm_ver=$ver
		elif [ $i -eq $rpm_running ]; then
			echo "Keeping running RPM kernel $ver"
			backup_rpm_ver=$ver
		else
			echo -n "Removing kernel RPM $ver..."
			# This will remove *all* kernel* packages with this
			# release string, including things like kernel-tools
			# which are not usually installed multiple times.
			# This is OK because we always keep the most recent
			# RPM, which is the only version of things like
			# kernel-tools that is supposed to be installed
			rpm -qa | grep $ver | xargs rpm -e
			echo "done."
		fi
	done
	pushd /boot
	# Remove all of the kdump images and rescue images, this needs to
	# be before the next step or it pollutes our version list
	rm -f *kdump.img *-rescue-*
	# We should only have two rpm versions still installed, so all of
	# the vmlinuz- files in /boot should belong to either one of those
	# two rpms, or devel kernels.  We assume that the total list of
	# kernels minus the two saved rpm versions is our list of devel
	# kernels, then we sort those to get the two most recent ones
	VERSIONS=""
	for i in vmlinuz-*; do
		ver=`echo $i | cut -f 2- -d '-'`
		[ -z "$ver" ] && continue
		if [ $ver = "$latest_rpm_ver" ]; then
			echo "Skipping $ver, not a devel kernel"
			continue
		elif [ $ver = "$backup_rpm_ver" ]; then
			echo "Skipping $ver, not a devel kernel"
			continue
		fi
		echo "Adding devel kernel $ver"
		if [ -z "$VERSIONS" ]; then
			VERSIONS="$ver"
		else
			VERSIONS="$VERSIONS $ver"
		fi
	done
	VERSIONS=`echo $VERSIONS | tr '[:blank:]' '\n' | sort -V --reverse`
	i=0
	for ver in $VERSIONS; do
		let i++
		if [ $i -eq 1 -a $ver = "$RUNNING_VER" ]; then
			echo "Keeping latest/running devel kernel $ver"
			latest_devel_ver=$ver
		elif [ $i -eq 1 ]; then
			echo "Keeping latest devel kernel $ver"
			latest_devel_ver=$ver
		elif [ $ver = "$RUNNING_VER" ]; then
			echo "Keeping running devel kernel $ver"
		elif [ $ver = "$latest_rpm_ver" ]; then
			echo "Keeping latest RPM kernel $ver"
		elif [ $ver = "$backup_rpm_ver" ]; then
			echo "Keeping backup RPM kernel $ver"
		else
			echo "Removing devel kernel $ver"
			rm -f /boot/*${ver}*
			rm -fr /lib/modules/${ver}
		fi
	done
	# Now remove the possible stale symlinks
	find . -maxdepth 1 -type l -delete
	popd
	pushd /lib/modules
	shopt -s nullglob
	for i in *; do
		if [ $i = "$latest_rpm_ver" ]; then
			echo "Keeping latest RPM kernel $i module dir"
		elif [ $i = "$backup_rpm_ver" ]; then
			echo "Keeping backup RPM kernel $i module dir"
		elif [ $i = "$latest_devel_ver" ]; then
			echo "Keeping latest devel kernel $i module dir"
		elif [ $i = $RUNNING_VER ]; then
			echo "Keeping running devel kernel $i module dir"
		else
			echo "Removing unknown/stale module dir $i"
			rm -fr $i
		fi
	done
	shopt -u nullglob
	popd
	[ -d /boot/grub2 ] && grub2-mkconfig -o /boot/grub2/grub.cfg
}

grub2_set_boot() {
	grep ^menuentry /boot/grub2/grub.cfg | awk -v version=$1 \
	'BEGIN {
		i = 0
	}
	{
		if (index($0, version)) {
			printf "Found "version" at index "i" in ";
			printf "grub2.cfg; setting default boot\n";
			exit(system("grub2-set-default "i));
		}
		i++
	}'
}

# idk - Install Development Kernel
#   Install a development kernel from a git repo.  Check for space first,
#   run clean_kernels above if less than 100MB is available on /boot.
idk() {
	avail=$(df --output=avail /boot | tail -1)
	[ "$avail" -lt 102400 ] && clean_kernels
	make -j64 modules_install
	restorecon -v -R /lib/firmware /lib/modules
	make install
	ins_ver=$(eval echo $(cat include/generated/utsrelease.h | \
		awk '{ print $3 }'))
	# Grub2 support is here...need to add support for more boot
	# loaders
	[ -f /boot/grub2/grub.cfg ] && grub2_set_boot $ins_ver
}

if [ ! -x "`which rhts-reboot`" ]; then
function rhts-reboot()
{
	if [ "$1" = "-r" ]; then
		if [ -f /root/EFI_BOOT_ENTRY.TXT ]; then
			efibootmgr -n `cat /root/EFI_BOOT_ENTRY.TXT`
		else
			efibootmgr -n `efibootmgr | grep BootCurrent | cut -f 2`
		fi
	fi
	/sbin/shutdown $*
}
fi
