FROM fedora:40

ENV ANSIBLE_HOST_KEY_CHECKING=False

RUN dnf -y update && dnf -y install ansible ansible-lint git python3 python3-jmespath python3-paramiko vim sshpass

COPY requirements.yml /tmp/ansible-requirements.yml

RUN ansible-galaxy collection install -r /tmp/ansible-requirements.yml