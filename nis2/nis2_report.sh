#!/bin/bash
# nis2_compliance_report.sh — raport zgodności NIS2 per agent
# Użycie: ./nis2_compliance_report.sh <agent_id>

WAZUH_API="https://localhost:55000"
AGENT_ID="${1:-001}"

TOKEN=$(curl -s -u wazuh-wui:MySecurePass -k -X POST \
  "${WAZUH_API}/security/user/authenticate" | jq -r '.data.token')

echo "========================================="
echo " NIS2/UKSC Compliance Report"
echo " Agent: ${AGENT_ID}"
echo " Date: $(date +%F_%T)"
echo "========================================="

# 1. SCA results
echo ""
echo "--- SCA Compliance Score ---"
curl -s -k -X GET "${WAZUH_API}/sca/${AGENT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" | \
  jq '.data.affected_items[] | {
    policy: .name,
    score: .score,
    pass: .pass,
    fail: .fail,
    invalid: .invalid,
    total_checks: .total_checks
  }'

# 2. Critical vulnerabilities
echo ""
echo "--- Critical Vulnerabilities ---"
CRIT_COUNT=$(curl -s -k -X GET "${WAZUH_API}/vulnerability/${AGENT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" | \
  jq '[.data.affected_items[] | select(.severity=="Critical")] | length')
echo "Critical CVEs: ${CRIT_COUNT}"

curl -s -k -X GET "${WAZUH_API}/vulnerability/${AGENT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" | \
  jq '.data.affected_items[] | select(.severity=="Critical") |
  {cve: .cve, package: .name, cvss: .cvss3_score}' | head -20

# 3. Recent high-severity alerts (last 24h)
echo ""
echo "--- High Severity Alerts (last 24h) ---"
YESTERDAY=$(date -d '1 day ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -v-1d +%Y-%m-%dT%H:%M:%S)
curl -s -k -X GET \
  "${WAZUH_API}/alerts?q=agent.id=${AGENT_ID};rule.level>=10;timestamp>${YESTERDAY}&limit=20&sort=-rule.level" \
  -H "Authorization: Bearer ${TOKEN}" | \
  jq '.data.affected_items[] | {
    time: .timestamp,
    level: .rule.level,
    desc: .rule.description,
    mitre: .rule.mitre.id
  }'

# 4. Agent info
echo ""
echo "--- Agent Info ---"
curl -s -k -X GET "${WAZUH_API}/agents?q=id=${AGENT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" | \
  jq '.data.affected_items[] | {
    name, ip, os_name: .os.name, os_version: .os.version,
    status, last_keep_alive, group
  }'

echo ""
echo "========================================="
echo " Report complete."
echo "========================================="
