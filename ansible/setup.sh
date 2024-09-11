#!/bin/bash
export LC_ALL=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8

yum install -y python3 python3-pip
python3 -m pip install --upgrade pip
python3 -m pip install wheel "ansible>=4"
mv /usr/local/bin/ansible* /usr/bin

cd /root/fsdp_setup/ansible

chmod +x run.sh
cp run_fsdp_setup.service /etc/systemd/system/run_fsdp_setup.service

systemctl enable run_fsdp_setup.service