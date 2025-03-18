#!/usr/bin/env python3

import sys
import json
import requests

JIRA_URL = "https://wazuhlegend.atlassian.net/rest/api/2/issue"
JIRA_USER = "jira-user@example.com"
JIRA_TOKEN = "your_jira_api_token"
PROJECT_KEY = "CYB"

import base64
import json
import sys

def send_to_jira(alert):
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Basic <BASE64_ENCODED_CREDENTIALS>"
    }
    payload = {
        "fields": {
            "project": {"key": "YOUR_PROJECT_KEY"},
            "summary": alert["rule"]["description"],
            "description": f"Alert details:\n{json.dumps(alert, indent=4)}",
            "issuetype": {"name": "Bug"},
            "priority": {"name": "High"}
        }
    }

    response = requests.post(JIRA_URL, json=payload, headers=headers)

    if response.status_code != 201:
        print("Error creating issue in Jira:", response.content, file=sys.stderr)

if __name__ == "__main__":
    alert = json.load(sys.stdin)
    send_to_jira(alert)
