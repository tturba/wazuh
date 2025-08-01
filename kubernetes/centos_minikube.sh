#!/bin/bash
set -e

echo "[1/9] Wyłączanie SELinux..."
setenforce 0 || true
sed -i --follow-symlinks 's/^SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

echo "[2/9] Instalacja narzędzi i Dockera..."
dnf install -y yum-utils wget tar git conntrack-tools
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# --- POCZĄTEK POPRAWKI ---
echo "[2b/9] Konfiguracja sterownika cgroup dla Dockera..."
cat <<EOF | tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

echo "[2c/9] Uruchamianie Dockera..."
systemctl daemon-reload
systemctl enable --now docker
# --- KONIEC POPRAWKI ---


echo "[3/9] Instalacja kubectl..."
# UWAGA: Wersja k8s, którą próbujesz usunąć w kroku 9, to v1.33.1. Użyj pasującej wersji kubectl.
curl -LO https://dl.k8s.io/release/v1.33.1/bin/linux/amd64/kubectl
chmod +x kubectl && mv kubectl /usr/local/bin/

echo "[4/9] Instalacja crictl..."
CRICTL_VERSION="v1.33.0" # Użyj wersji pasującej do Kubernetes
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-$CRICTL_VERSION-linux-amd64.tar.gz
tar zxvf crictl-$CRICTL_VERSION-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-$CRICTL_VERSION-linux-amd64.tar.gz

echo "[5/9] Instalacja cri-dockerd..."
CRIDOCKERD_VERSION="0.3.14"
wget https://github.com/Mirantis/cri-dockerd/releases/download/v$CRIDOCKERD_VERSION/cri-dockerd-$CRIDOCKERD_VERSION.amd64.tgz
tar xvf cri-dockerd-$CRIDOCKERD_VERSION.amd64.tgz
mv cri-dockerd/cri-dockerd /usr/local/bin/
chmod +x /usr/local/bin/cri-dockerd
rm -rf cri-dockerd cri-dockerd-$CRIDOCKERD_VERSION.amd64.tgz

echo "[6/9] Konfiguracja systemd dla cri-dockerd..."
wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/v$CRIDOCKERD_VERSION/packaging/systemd/cri-docker.service
wget https://raw.githubusercontent.com/Mirantis/cri-dockerd/v$CRIDOCKERD_VERSION/packaging/systemd/cri-docker.socket
mv cri-docker.service /etc/systemd/system/
mv cri-docker.socket /etc/systemd/system/
sed -i 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service
systemctl daemon-reload
# --- POCZĄTEK POPRAWKI ---
echo "[6b/9] Restartowanie i włączanie cri-dockerd..."
systemctl restart docker # Upewnij się, że Docker działa z nową konfiguracją
systemctl enable --now cri-docker.socket cri-docker.service

# Dodajmy krótką przerwę i weryfikację, czy usługa faktycznie działa
sleep 5
if ! systemctl is-active --quiet cri-docker.service; then
    echo "❌ Usługa cri-docker.service nie uruchomiła się poprawnie."
    journalctl -u cri-docker.service -n 50 --no-pager
    exit 1
fi
echo "✅ Usługa cri-docker.service jest aktywna."
# --- KONIEC POPRAWKI ---

echo "[7/9] Instalacja Minikube..."
MINIKUBE_VERSION="v1.36.0"
curl -Lo minikube https://github.com/kubernetes/minikube/releases/download/$MINIKUBE_VERSION/minikube-linux-amd64
chmod +x minikube && mv minikube /usr/local/bin/

echo "[8/9] Instalacja CNI plugins..."
CNI_VERSION="v1.4.1"
mkdir -p /opt/cni/bin
wget https://github.com/containernetworking/plugins/releases/download/$CNI_VERSION/cni-plugins-linux-amd64-$CNI_VERSION.tgz
tar xvf cni-plugins-linux-amd64-$CNI_VERSION.tgz -C /opt/cni/bin/
rm -f cni-plugins-linux-amd64-$CNI_VERSION.tgz

echo "[9/9] Usuwanie starych profili Minikube..."
minikube delete --all --purge || true

echo "[FINAL] Uruchamianie Minikube z Dockerem + cri-dockerd..."
# Wersja Minikube v1.36.0 domyślnie używa Kubernetes v1.30.0.
# Jeśli chcesz konkretną wersję, dodaj flagę --kubernetes-version=v1.33.1
minikube start --driver=none --container-runtime=docker --cri-socket=unix:///var/run/cri-dockerd.sock

echo "✅ Minikube powinno teraz odpalić bez błędów."
