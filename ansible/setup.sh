#!/bin/bash

if [ -f /etc/fedora-release ]; then
	OS=fedora
	RELEASE=`cat /etc/fedora-release | grep release | cut -f 3 -d ' '`
else
	OS=rhel
	RELEASE=`cat /etc/redhat-release | grep release | grep -o '[0-9]*\.[0-9]' | cut -f 1 -d '.'`
fi

if [ "$OS" = rhel -a "$RELEASE" != 7 ] || [ "$OS" = fedora -a "$RELEASE" -lt 36 ]; then
    yum install -y ansible
else
    pip3 install --upgrade pip
    pip3 install ansible>=4
    # mv /usr/local/bin/ansible* /usr/bin
fi

cd /root/fsdp_setup/ansible

chmod +x run.sh
cp run_fsdp_setup.service /etc/systemd/system/run_fsdp_setup.service

systemctl enable run_fsdp_setup.service