# FSDP Setup with Ansible

This is the Ansible Playbook used to setup the FSDP nodes. This is pretty much a direct translation of rdma-functions.sh where each function in rdma-functions.sh is a task in this Playbook.

## Ansible structure

This Ansible Playbook is structured into four roles: common, dhcp, interfaces, and nfs which each contain related tasks to be run. The entry point is setup_hosts.yml, which runs all four of these roles. There is the group_vars directory, which holds variables that all nodes need, and the host_var directory, which holds variables for each individual node.

Some functions in rdma-functions.sh aren't being utilized anywhere, so they are kept in the unused_tasks directory.

## Execution

This playbook is being run through the FSDP Beaker Snippets. The beaker snippets create the run_fsdp_setup systemd service, which will run once on the first boot. This service is then what runs the Ansible Playbook.