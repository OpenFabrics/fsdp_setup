#! bin/sh

systemctl restart dhcpd

#if the command successfully started dhcp it should return 0
#found how to do this on https://shapeshed.com/unix-exit-codes/
if [ $? -eq 0 ]
then
    echo "Dhcp4 restarted successfully."
    exit 0
else
    $?
    echo "There was an error restarting Dhcp4."
    exit 1

