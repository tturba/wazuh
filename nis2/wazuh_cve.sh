#!/bin/bash
# NIS2 Art.21(2)(e) — raport krytycznych podatności per agent
# Użycie: ./vuln_report.sh <agent_id>

WAZUH_API="https://localhost:55000"
AGENT_ID="${1:-003}"

# Autentykacja
TOKEN=$(curl -s -u wazuh-wui:MySecurePass -k -X POST \
  "${WAZUH_API}/security/user/authenticate" | jq -r '.data.token')

# Pobranie krytycznych CVE
echo "=== Krytyczne podatności dla agenta ${AGENT_ID} ==="
curl -s -k -X GET "${WAZUH_API}/vulnerability/${AGENT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" | \
  jq '.data.affected_items[] | select(.severity=="Critical") |
  {
    cve: .cve,
    package: .name,
    version: .version,
    cvss: .cvss3_score,
    title: .title,
    fix: .condition
  }'

# Podsumowanie
echo ""
echo "=== Podsumowanie ==="
curl -s -k -X GET "${WAZUH_API}/vulnerability/${AGENT_ID}/summary" \
  -H "Authorization: Bearer ${TOKEN}" | \
  jq '.data'
