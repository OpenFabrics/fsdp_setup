#!/bin/bash
export ANSIBLE_HOST_KEY_CHECKING=False
cd /root/fsdp_setup/ansible

ansible-playbook -i inventory --diff -v setup_host.yml --limit "$(hostname)" --connection=local

systemctl disable run_fsdp_setup.service

reboot