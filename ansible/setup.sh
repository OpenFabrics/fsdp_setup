#!/bin/bash

export LC_ALL=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export ANSIBLE_HOST_KEY_CHECKING=False

yum install -y python3 python3-pip
python3 -m pip install --upgrade pip
python3 -m pip install --upgrade wheel
python3 -m pip install --upgrade pyopenssl "ansible>=4"
mv /usr/local/bin/ansible* /usr/bin

cd /root/fsdp_setup/ansible

ansible-playbook -i inventory --diff -v setup_host.yml --limit "$(cat /etc/hostname)" --connection=local