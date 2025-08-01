#!/var/ossec/framework/python/bin/python3
import json
from socket import socket, AF_UNIX, SOCK_DGRAM
from flask import Flask, request
# CONFIG
PORT     = 8080
CERT     = '/var/ossec/integrations/kubernetes-webhook/server.crt'
CERT_KEY = '/var/ossec/integrations/kubernetes-webhook/server.key'
# Analysisd socket address
socket_addr = '/var/ossec/queue/sockets/queue'
def send_event(msg):
    string = '1:k8s:{0}'.format(json.dumps(msg))
    sock = socket(AF_UNIX, SOCK_DGRAM)
    sock.connect(socket_addr)
    sock.send(string.encode())
    sock.close()
    return True
app = Flask(__name__)
context = (CERT, CERT_KEY)
@app.route('/', methods=['POST'])
def webhook():
    if request.method == 'POST':
        if send_event(request.json):
            print("Request sent to Wazuh")
        else:
            print("Failed to send request to Wazuh")
    return "Webhook received!"
if __name__ == '__main__':
    app.run(host='<wazuh_server_ip>', port=PORT, ssl_context=context)
