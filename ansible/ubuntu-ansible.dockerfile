# basing on 
# https://medium.com/@giovannyorjuel2/unleashing-ansibles-power-inside-docker-containers-8acc8c1d5857

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install package and ansible
# from https://docs.ansible.com/ansible/latest/installation_guide/installation_distros.html
RUN apt-get update && \
  apt-get install -y software-properties-common && \
  apt-add-repository --yes --update ppa:ansible/ansible && \
# modified by giovannyorjuel2
  apt install -y ansible sshpass bash && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

  WORKDIR /ansible
  COPY ./playbooks /ansible/playbooks

