# DHCPD API Service

This API allows scripts running on the nodes within the FSDP cluster as
unprivledged users to make changes to the dhcpd services on the fabrics
running on the builder-00.ofa.iol.unh.edu system.

## API Endpoints

Action to be Performed | HTTP Route | HTTP Method
-----------------------|------------|--------------
Get a list of node configuration files | builder-00.ofa.iol.unh.edu:8080/hosts.d | GET
Restart the DHCP4 service |  builder-00.ofa.iol.unh.edu:8080/restartDhcp4Service | POST
Restart the DHCP6 service | builder-00.ofa.iol.unh.edu:8080/restartDhcp6Service | POST
Check the status of DHCP4 and DHCP6 services | builder-00.ofa.iol.unh.edu:8080/checkDhcpStatus | POST
Rebuild the DHCP config | builder-00.ofa.iol.unh.edu:8080/rebuildDhcp | POST
Delete a node config file | builder-00.ofa.iol.unh.edu:8080/hosts.d/*nameOfFileToDelete* | DELETE

### Get a list of node configuration files

``http://builder-00.ofa.iol.unh.edu:8080/hosts.d`` - Method = GET

This should return a 200 and a json object that contains the list of the
file names for the node configuration files in the hosts.d directory.

### Restart the DHCP service

``http://builder-00.ofa.iol.unh.edu:8080/restartDhcp4Service`` - Method = POST

This route should restart the DHCP 4 service and either return a 200
response if it was successful or a 500 response if there was an error
while restarting.

``http://builder-00.ofa.iol.unh.edu:8080/restartDhcp6Service`` - Method = POST

This route, much like the previous, should restart the DHCP 6 service and
either return a 200 response if it was successful or a 500 response if
there was an error while restarting.

* ### Check the status of DHCP4 and DHCP6 services

``http://builder-00.ofa.iol.unh.edu:8080/checkDhcpStatus`` - Method = POST

This route should query the status of both DHCP4 and DHCP6 and it will either
return a 200 response with a json containing the status of both if it was able
to find the status of both, a 206 response if it found the status of one but
failed to find the status of the other, or a 500 response if there was an error
and it failed to find the status of either.

* ### Rebuild the DHCP config

``http://builder-00.ofa.iol.unh.edu:8080/rebuildDhcp`` - Method = POST

This route will rebuild the DHCP configuration file and it will return a
200 status if it was successful, a 502 status if it was unable to find the
node configuration files it needs, or a 500 status if the node files were
found but there was an error in the rebuilding process.

* ### Delete a node config file

``http://builder-00.ofa.iol.unh.edu:8080/hosts.d/nameOfFileToDelete`` - Method = DELETE

This route will delete the specific node configuration file that matches the
name that you give it and return a 200OK response if it was successful, a 404
response if it was unable to find the file you were trying to delete, or a
500 response if the file was found but there was an error deleting it.

## Installation

1. The contents of this directory should be copied to the /opt/dhcpd_api directory
on the builder-00.ofa.iol.unh.edu.
1. After you've done that, you'll need to create a python virtual environment
folder called "venv" in the /opt/dhcpd_api directory and install the dependancies
from the requirements.txt file in that environment.
1. The API will be running under the systems user dhcp_api so if there isn't an
existing system user under that name you'll need to create one, using
``useradd --system --shell /sbin/nologin --home-dir /opt/dhcpd_api -M dhcpapi``.
1. From there you need to move the "dhcp_api" file into /etc/sudoers.d/ directory
to ensure that the user the API is running on will have the necessary permissions.
1. Then you just need to move the dhcp_api.service file into the /etc/systemd/system
directory and once you do a daemon-reload it should run as a service and be operational.
1. Ensure the configured API port (default 8080) is open within the firewall
configuration on the server.

NOTE: If you do not place the API files into the /opt/dhcpd_api directory you will need
to change the dhcp_api.service file to accuractely reflect the new paths.  Similar
changed would be necessary if you change the assigned system username.
