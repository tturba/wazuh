#!/bin/bash
set -e

echo "[1/11] Wyłączanie SELinux..."
setenforce 0 || true
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/sysconfig/selinux

echo "[2/11] Instalacja narzędzi bazowych..."
dnf install -y yum-utils wget curl conntrack iptables tar git

echo "[3/11] Instalacja Dockera..."
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker

echo "[4/11] Instalacja kubeadm, kubelet i kubectl..."
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl
EOF
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

echo "[5/11] Instalacja crictl (v1.32.0)..."
CRICTL_VERSION="v1.32.0"
curl -LO https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz
tar zxvf crictl-${CRICTL_VERSION}-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-${CRICTL_VERSION}-linux-amd64.tar.gz

echo "[6/11] Instalacja cri-dockerd (v0.3.14)..."
CRID_VERSION="0.3.14"
wget https://github.com/Mirantis/cri-dockerd/releases/download/v${CRID_VERSION}/cri-dockerd-${CRID_VERSION}.amd64.tgz
tar xvf cri-dockerd-${CRID_VERSION}.amd64.tgz
mv cri-dockerd/cri-dockerd /usr/local/bin/
chmod +x /usr/local/bin/cri-dockerd
rm -rf cri-dockerd cri-dockerd-${CRID_VERSION}.amd64.tgz

echo "[6.1/11] Konfiguracja systemd dla cri-dockerd..."
wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/v${CRID_VERSION}/packaging/systemd/cri-docker.service
wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/v${CRID_VERSION}/packaging/systemd/cri-docker.socket
mv cri-docker.service cri-docker.socket /etc/systemd/system/
sed -i 's:/usr/bin/cri-dockerd:/usr/local/bin/cri-dockerd:' /etc/systemd/system/cri-docker.service
systemctl daemon-reload
systemctl enable --now cri-docker.service
systemctl enable --now cri-docker.socket

echo "[7/11] Instalacja CNI plugins..."
CNI_VERSION="v1.4.0"
mkdir -p /opt/cni/bin
curl -LO https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz
tar -C /opt/cni/bin -xzvf cni-plugins-linux-amd64-${CNI_VERSION}.tgz
rm -f cni-plugins-linux-amd64-${CNI_VERSION}.tgz

echo "[8/11] Instalacja kubectl (najnowsza wersja stabilna)..."
KUBECTL_VER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

echo "[9/11] Instalacja Minikube (v1.36.0)..."
curl -Lo minikube https://github.com/kubernetes/minikube/releases/download/v1.36.0/minikube-linux-amd64
chmod +x minikube
mv minikube /usr/local/bin/

echo "[10/11] Wstępne czyszczenie poprzednich profili Minikube..."
minikube delete --all || true

echo "[11/11] Uruchamianie Minikube z Dockerem + cri-dockerd..."
minikube start --driver=none \
  --container-runtime=docker \
  --cri-socket=unix:///var/run/cri-dockerd.sock

echo "Instalacja zakończona pomyślnie!"
kubectl version --client --output=yaml
minikube status
