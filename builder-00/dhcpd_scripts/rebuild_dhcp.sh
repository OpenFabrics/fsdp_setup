#!/bin/bash
#here $1 represents the name of the node config file 
cat /var/lib/tftpboot/hosts.d/$1 >> /etc/dhcp/dhcpd.conf
