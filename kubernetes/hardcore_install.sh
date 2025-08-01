#!/bin/bash
set -e

### ========================
### KONFIGURACJA
### ========================
WAZUH_SERVER_IP="192.168.88.252"     # IP Wazuh Managera
MINIKUBE_VERSION="v1.33.1"           # https://github.com/kubernetes/minikube/releases
KUBECTL_VERSION="v1.31.1"            # https://github.com/kubernetes/kubernetes/releases
CRICTL_VERSION="v1.30.0"             # https://github.com/kubernetes-sigs/cri-tools/releases

### ========================
echo "[1/14] Aktualizacja systemu"
sudo apt update && sudo apt upgrade -y

echo "[2/14] Instalacja wymaganych pakietów"
sudo apt install -y ca-certificates curl gnupg lsb-release apt-transport-https conntrack python3 python3-pip git make golang

echo "[3/14] Instalacja Docker"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable docker
sudo systemctl start docker

echo "[4/14] Instalacja cri-dockerd"
if [ ! -f /usr/local/bin/cri-dockerd ]; then
  git clone https://github.com/Mirantis/cri-dockerd.git
  cd cri-dockerd
  make
  sudo install -o root -g root -m 0755 cri-dockerd /usr/local/bin/cri-dockerd
  sudo cp -a packaging/systemd/* /etc/systemd/system
  sudo sed -i 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service
  sudo systemctl daemon-reload
  sudo systemctl enable cri-docker.service
  sudo systemctl enable --now cri-docker.socket
  cd ..
  rm -rf cri-dockerd
fi

echo "[5/14] Instalacja kubectl"
curl -sLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

echo "[6/14] Instalacja Minikube"
curl -sLo minikube "https://github.com/kubernetes/minikube/releases/download/${MINIKUBE_VERSION}/minikube-linux-amd64"
chmod +x minikube
sudo mv minikube /usr/local/bin/

echo "[7/14] Instalacja crictl"
curl -sLO "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz"
tar zxvf crictl-${CRICTL_VERSION}-linux-amd64.tar.gz
sudo mv crictl /usr/local/bin/
rm crictl-${CRICTL_VERSION}-linux-amd64.tar.gz

echo "[8/14] Uruchamianie Minikube"
sudo minikube start --driver=none --container-runtime=docker --cri-socket=unix:///var/run/cri-dockerd.sock

echo "[9/14] Tworzenie katalogu audytu"
sudo mkdir -p /etc/kubernetes/audit

cat << 'EOF' | sudo tee /etc/kubernetes/audit/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
  resources:
  - group: ""
    resources: ["pods", "services", "namespaces"]
- level: RequestResponse
  verbs: ["create", "update", "patch", "delete"]
EOF

cat << EOF | sudo tee /etc/kubernetes/audit/audit-webhook.yaml
apiVersion: audit.k8s.io/v1
kind: Webhook
webhook:
  throttle:
    qps: 10
    burst: 15
  sink:
    http:
      url: "http://${WAZUH_SERVER_IP}:55000"
EOF

echo "[10/14] Modyfikacja kube-apiserver.yaml"
KUBE_APISERVER="/etc/kubernetes/manifests/kube-apiserver.yaml"
sudo sed -i '/- kube-apiserver/a\    - --audit-policy-file=/etc/kubernetes/audit/audit-policy.yaml' $KUBE_APISERVER
sudo sed -i '/- kube-apiserver/a\    - --audit-webhook-config-file=/etc/kubernetes/audit/audit-webhook.yaml' $KUBE_APISERVER
sudo sed -i '/- kube-apiserver/a\    - --audit-webhook-batch-max-wait=5s' $KUBE_APISERVER
sudo sed -i '/- kube-apiserver/a\    - --audit-webhook-batch-max-size=10' $KUBE_APISERVER

echo "[11/14] Dodawanie dekoderów do Wazuh"
sudo tee /var/ossec/etc/decoders/k8s-audit.xml > /dev/null << 'EOD'
<decoder name="k8s-audit">
  <program_name>k8s-audit</program_name>
  <type>json</type>
</decoder>
<decoder name="k8s-audit-verb">
  <parent>k8s-audit</parent>
  <regex>\\"verb\\":\\"([a-zA-Z]+)\\"</regex>
  <order>verb</order>
</decoder>
<decoder name="k8s-audit-resource">
  <parent>k8s-audit</parent>
  <regex>\\"resource\\":\\"([a-zA-Z]+)\\"</regex>
  <order>resource</order>
</decoder>
<decoder name="k8s-audit-namespace">
  <parent>k8s-audit</parent>
  <regex>\\"namespace\\":\\"([a-zA-Z0-9-_]+)\\"</regex>
  <order>namespace</order>
</decoder>
<decoder name="k8s-audit-user">
  <parent>k8s-audit</parent>
  <regex>\\"username\\":\\"([^\\"]+)\\"</regex>
  <order>username</order>
</decoder>
EOD

echo "[12/14] Dodawanie reguł do Wazuh"
sudo tee /var/ossec/etc/rules/k8s-audit_rules.xml > /dev/null << 'EOR'
<group name="k8s_audit,">
  <rule id="910001" level="5">
    <decoded_as>k8s-audit</decoded_as>
    <field name="verb">create</field>
    <description>Kubernetes: Tworzenie zasobu - $(resource) w namespace $(namespace) przez $(username)</description>
    <group>create,</group>
  </rule>
  <rule id="910002" level="7">
    <decoded_as>k8s-audit</decoded_as>
    <field name="verb">delete</field>
    <description>Kubernetes: Usuwanie zasobu - $(resource) w namespace $(namespace) przez $(username)</description>
    <group>delete,</group>
  </rule>
  <rule id="910003" level="6">
    <decoded_as>k8s-audit</decoded_as>
    <field name="verb">update|patch</field>
    <description>Kubernetes: Modyfikacja zasobu - $(resource) w namespace $(namespace) przez $(username)</description>
    <group>update,</group>
  </rule>
  <rule id="910004" level="10">
    <decoded_as>k8s-audit</decoded_as>
    <field name="namespace">kube-system</field>
    <description>Kubernetes: Działanie w kube-system - $(verb) $(resource) przez $(username)</description>
    <group>critical,</group>
  </rule>
</group>
EOR

echo "[13/14] Instalacja listenera webhooka"
sudo tee /usr/local/bin/k8s_audit_listener.py > /dev/null << 'EOF'
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        with open("/var/ossec/logs/k8s-audit.log", "ab") as f:
            f.write(post_data + b"\n")
        self.send_response(200)
        self.end_headers()

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 55000), WebhookHandler)
    print("Listening on port 55000...")
    server.serve_forever()
EOF
sudo chmod +x /usr/local/bin/k8s_audit_listener.py

echo "[14/14] Restart Wazuh i uruchomienie listenera"
sudo systemctl restart wazuh-manager
nohup python3 /usr/local/bin/k8s_audit_listener.py &

echo "✅ Instalacja zakończona. Minikube + audyt Kubernetes podłączony do Wazuh."
