# DHCPD API Service

This API allows scripts running on the nodes within the FSDP cluster as
unprivledged users to make changes to the dhcpd services on the fabrics
running on the builder-00.ofa.iol.unh.edu system.

## API Endpoints

## Installation

The contents of this directory should be copied to the /opt/dhcpd_api directory
on the builder-00.ofa.iol.unh.edu.  If an alternate path is used, the systemd
.service will will need to be changed appropriately.
