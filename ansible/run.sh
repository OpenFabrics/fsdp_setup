#!/bin/bash

export ANSIBLE_HOST_KEY_CHECKING=False
cd /root/fsdp_setup/ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory --diff -v setup_host.yml --limit "$(hostname)" --connection=local