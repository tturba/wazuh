#!/bin/bash
# incident_report.sh — eksport timeline incydentu do pliku JSON
# NIS2 Art.21(2)(b) — materiał do raportu S46
# Użycie: ./incident_report.sh "2026-04-14T08:00:00" "2026-04-14T12:00:00"

WAZUH_API="https://localhost:55000"
INCIDENT_START="${1:-2026-04-14T08:00:00}"
INCIDENT_END="${2:-2026-04-14T12:00:00}"
OUTPUT="incident_report_$(date +%F_%H%M).json"
MIN_LEVEL=10

# Autentykacja
TOKEN=$(curl -s -u wazuh-wui:MySecurePass -k -X POST \
  "${WAZUH_API}/security/user/authenticate" | jq -r '.data.token')

# Pobranie alertów z zakresu czasowego
echo "Pobieranie alertów z ${INCIDENT_START} do ${INCIDENT_END} (level >= ${MIN_LEVEL})..."

curl -s -k -X GET \
  "${WAZUH_API}/alerts?q=timestamp>${INCIDENT_START};timestamp<${INCIDENT_END};rule.level>=${MIN_LEVEL}&limit=500&sort=-timestamp" \
  -H "Authorization: Bearer ${TOKEN}" | \
  jq '[.data.affected_items[] | {
    timestamp: .timestamp,
    rule_id: .rule.id,
    rule_level: .rule.level,
    description: .rule.description,
    mitre_ids: .rule.mitre.id,
    mitre_tactics: .rule.mitre.tactic,
    agent_name: .agent.name,
    agent_ip: .agent.ip,
    src_ip: .data.srcip,
    dst_ip: .data.dstip,
    groups: .rule.groups,
    full_log: .full_log
  }]' > "${OUTPUT}"

# Podsumowanie
ALERT_COUNT=$(jq length "${OUTPUT}")
echo "=== Raport zapisany: ${OUTPUT} ==="
echo "=== Liczba alertów: ${ALERT_COUNT} ==="
echo ""
echo "Top 5 reguł:"
jq -r '[group_by(.rule_id)[] | {rule: .[0].description, count: length}] | sort_by(-.count) | .[0:5][] | "\(.count)x — \(.rule)"' "${OUTPUT}"
echo ""
echo "Dotknięci agenci:"
jq -r '[.[].agent_name] | unique | .[]' "${OUTPUT}"
echo ""
echo "MITRE ATT&CK:"
jq -r '[.[].mitre_ids // [] | .[]] | unique | .[]' "${OUTPUT}"
