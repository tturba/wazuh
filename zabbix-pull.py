import requests
import json
import sys

WAZUH_API_URL = "http://$WAZUHIP:55000" 
WAZUH_API_USER = "wazuh" 
WAZUH_API_PASSWORD = "passw0rdsecret"  
VERIFY_SSL = True  

def get_wazuh_alerts():
    url = f"{WAZUH_API_URL}/alerts/summary?pretty"
    headers = {'Content-Type': 'application/json'}

    try:
        response = requests.get(url, headers=headers, auth=(WAZUH_API_USER, WAZUH_API_PASSWORD), verify=VERIFY_SSL)
        response.raise_for_status() 
        alerts_summary = response.json()
        print(json.dumps(alerts_summary, indent=2))
     
    except requests.exceptions.HTTPError as errh:
        print("Http Error:", errh)
    except requests.exceptions.ConnectionError as errc:
        print("Error Connecting:", errc)
    except requests.exceptions.Timeout as errt:
        print("Timeout Error:", errt)
    except requests.exceptions.RequestException as err:
        print("OOps: Something Else", err)

if __name__ == "__main__":
    get_wazuh_alerts()
