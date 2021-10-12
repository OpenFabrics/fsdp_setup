#! bin/sh

systemctl restart dhcpd6

#if the command successfully started dhcp it should return 0
#found how to do this on https://shapeshed.com/unix-exit-codes/
if [ $? -eq 0 ]
then
    exit 0
else
    exit 1