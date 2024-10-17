#!/usr/bin/python3

import requests
import json
import urllib3
import sys
import os
import datetime
import subprocess

LOG_FILE = "/var/ossec/logs/active-responses.log"
ADD_COMMAND = 1
CONTINUE_COMMAND = 2
ABORT_COMMAND = 3
OS_SUCCESS = 0
OS_INVALID = -1
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
KEY = <ipdb key here>

class message:
    def __init__(self):
        self.alert = ""
        self.command = 0

def testaipdb(ip):
    # Check the IP in the AbuseIPDB database. This is to avoid blocking legitimate IP addresses
    url = 'https://api.abuseipdb.com/api/v2/check'
    headers = { 'Accept': 'application/json', 'Key': KEY }
    query = { 'ipAddress': ip }
    response = requests.get(url=url, headers=headers, params=query, verify=False)

    decodeResponse = json.loads(response.text)
    score = decodeResponse['data']['abuseConfidenceScore']
    reports = decodeResponse['data']['totalReports']
    if score >=1 and reports >= 1: # Score is the confidence of abuse. If it was reported more than once and the confidence is higher than zero, it will be blocked.
        return 1
    else:
        return 0

def setup_and_check_msg(argv):
    # Read the message from STDIN, decode and read the command (we are only interested in the 'add' command).
    input_str = ""
    for line in sys.stdin:
        input_str = line
        break
    try:
        data = json.loads(input_str)
        write_log_file(argv[0], data)
    except ValueError:
        write_debug_file(argv[0], 'Decoding JSON has failed: invalid input format!')
        message.command = OS_INVALID
        return message
    message.alert = data
    command = data.get('command')
    if command == "add":
        message.command = ADD_COMMAND
    elif command == "delete":
        message.command == DELETE_COMMAND
    else:
        message.command == OS_INVALID
        write_debug_file(argv[0], f'Not a valid command: {command}')
    return message

def write_log_file(ar_name, msg):
    # Just log the activities
    with open(LOG_FILE, mode='a') as log_file:
        log_file.write(str(datetime.datetime.now().strftime('%Y/%m/%d %H:%M:%S')) + " " + ar_name + ": " + f"{msg}" + "\n")

def send_keys(argv, keys):
    # Here we get the relevant keys from the message and create our own message
    keys_msg = f"Alert:\n  Description: {keys[0]}\n  Agent: {keys[1]}\n  SourceIP: {keys[2]}"
    keys_msg_log = f"Alert: Description: {keys[0]}  Agent: {keys[1]} SourceIP: {keys[2]}"
    write_log_file(argv[0], keys_msg_log)
    sys.stdout.flush()

def send_message_telegram(argv, keys):
    # Send the alert via telegram. You need a Telegram bot for this.
    write_log_file(argv[0], "Sending message to telegram")
    print(keys)
    TOKEN=<your telegram token here>
    chat_id = <your chat ID here>
    url = f"https://api.telegram.org/bot{TOKEN}/sendMessage?chat_id={chat_id}&text={keys}"
    response = requests.get(url)
    if response.status_code != 200:
        print(f"Error: status code: {response.status_code}")
        print(f"Error message: {json.loads(response.content.decode())}")

def main(argv):
    write_log_file(argv[0], "Started")
    msg = setup_and_check_msg(argv)
    if msg.command < 0:
        sys.exit(OS_INVALID)
    if msg.command == ADD_COMMAND:
        write_log_file(argv[0], msg)
        alert = msg.alert['parameters']['alert']
        keys = [alert['rule']['description'], alert['agent']['name'], alert['data']['remote_addr']] #Extract from the alert only the keys we want
        send_keys(argv, keys)
        check = testaipdb(keys[2])
        if check == 1:
            #use nftables to block the IP
            subprocess.run(['systemctl', 'start', 'nftables']) 
            subprocess.run(["nft", "add", "rule", "inet", "filter", "input", "ip", f"saddr {keys[2]}", "drop"])
            send_message_telegram(argv, f"IP {keys[2]} blocked on server {keys[1]}") 

if __name__ == '__main__':
    main(sys.argv)
