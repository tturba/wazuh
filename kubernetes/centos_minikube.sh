#!/bin/bash

set -e

# 1. SELinux
setenforce 0
sed -i --follow-symlinks 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# 2. Instalacja containerd i wymaganych narzędzi
yum install -y containerd curl iptables

# 3. Włącz i uruchom containerd
systemctl enable containerd
systemctl start containerd

# 4. Konfiguracja containerd 
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# Ustaw systemd jako driver cgroup
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# 5. Pobranie i instalacja Minikube
curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
chmod +x minikube
mv minikube /usr/local/bin/

# 6. Uruchomienie Minikube w trybie none z containerd jako runtime
minikube delete || true
#minikube start --driver=none --container-runtime=containerd --cri-socket=unix:///run/containerd/containerd.sock
minikube start --driver=none --container-runtime=containerd
# 7. Sprawdzenie statusu klastra
kubectl cluster-info
kubectl get nodes


