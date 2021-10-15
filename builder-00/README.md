# DHCPD API Service

This API allows scripts running on the nodes within the FSDP cluster as
unprivledged users to make changes to the dhcpd services on the fabrics
running on the builder-00.ofa.iol.unh.edu system.

## API Endpoints

* ### Get a list of node configuration files
    **builder-00.iol.unh.edu:8080/hosts.d** - Method = GET

    This should return a 200OK and a json object that contains the list of the file names for the node configuration files in the hosts.d directory.

* ### Restart the DHCP service
    **builder-00.iol.unh.edu:8080/restartDhcp4Service** - Method = POST

    This route should restart the DHCP 4 service and either return a 200OK response if it was successful or a 500 response if there was an error while restarting.

    **builder-00.iol.unh.edu:8080/restartDhcp6Service** - Method = POST

    This route should restart, much like the previous, the DHCP 6 service and either return a 200OK response if it was successful or a 500 response if there was an error while restarting.

* ### Check the status of DHCP4 and DHCP6 services
    **builder-00.iol.unh.edu:8080/checkDhcpStatus** - Method = POST

    This route should query the status of both DHCP4 and DHCP6 and it will either return a 200 with a json containing the status of both if it was able to find the status of both, a 206 response if it found the status of one but failed to find the status of the other, or a 500 response if there was an error and it failed to find the status of either.

* ### Rebuild the DHCP config
    **builder-00.iol.unh.edu:8080/rebuildDhcp** - Method = POST

    This route will rebuild the DHCP configuration file and it will return a 200OK status if it was successful, a 502 status if it was unable to find the node configuration files it needs, or a 500 status if the node files were found but there was an error in the rebuilding process.

* ### Delete a node config file
    __builder-00.iol.unh.edu:8080/hosts.d/*nameOfFileToDelete*__ - Method = DELETE

    This route will delete the specific node configuration file that matches the name that you give it and return a 200OK response if it was successful, a 404 response if it was unable to find the file you were trying to delete, or a 500 response if the file was found but there was an error deleting it.

## Installation

The contents of this directory should be copied to the /opt/dhcpd_api directory
on the builder-00.ofa.iol.unh.edu.  If an alternate path is used, the systemd
.service will will need to be changed appropriately.
