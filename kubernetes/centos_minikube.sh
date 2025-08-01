#!/bin/bash
# Disable SELinux...
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux

# Install Docker
dnf install -y yum-utils
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker

# Install conntrack
dnf install -y conntrack

# Install cri‑dockerd v0.3.14
# (pobrać archiwum, rozpakować, kopia binarki + systemd, reload daemon)
wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.14/cri-dockerd-0.3.14.amd64.tgz
tar xzf cri-dockerd-0.3.14.amd64.tgz
install -o root -g root -m 0755 cri-dockerd/cri-dockerd /usr/local/bin/cri-dockerd
install cri-dockerd-0.3.14/packaging/systemd/* /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now cri-docker.service

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install Minikube v1.36.0
curl -Lo minikube https://github.com/kubernetes/minikube/releases/download/v1.36.0/minikube-linux-amd64
chmod +x minikube
mv minikube /usr/local/bin/

# Start Minikube
minikube start --driver=none --container-runtime=cri-dockerd
