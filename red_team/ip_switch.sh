#!/bin/bash
# ============================================
# Red Team - IP Alias 管理
# 用途: 被 MDR 封鎖後切換 IP 繼續攻擊
# MITRE ATT&CK: Defense Evasion (IP alias — no specific technique ID)
# ============================================

PRIMARY_IP="192.168.1.14"
ALIAS_IP="${2:-192.168.1.15}"
INTERFACE="wlp132s0"

case "$1" in
    add)
        echo "[*] Adding alias IP: $ALIAS_IP on $INTERFACE"
        sudo ip addr add "$ALIAS_IP/24" dev "$INTERFACE"
        echo "[+] Done. Current IPs:"
        ip addr show "$INTERFACE" | grep inet
        echo ""
        echo "[*] Demo flow:"
        echo "    1. Use $PRIMARY_IP to hit port 2222 (will be blocked by MDR)"
        echo "    2. Use $ALIAS_IP to hit port 9999:"
        echo "       python3 exploit.py <TARGET_IP> --bind-ip $ALIAS_IP"
        echo "       nc -s $ALIAS_IP -v <TARGET_IP> 4444"
        ;;
    remove)
        echo "[*] Removing alias IP: $ALIAS_IP"
        sudo ip addr del "$ALIAS_IP/24" dev "$INTERFACE"
        echo "[+] Done. Current IPs:"
        ip addr show "$INTERFACE" | grep inet
        ;;
    status)
        echo "[*] Current IPs on $INTERFACE:"
        ip addr show "$INTERFACE" | grep inet
        ;;
    *)
        echo "Usage: $0 {add|remove|status} [CUSTOM_IP]"
        echo ""
        echo "  add [IP]    - Add alias IP (default: 192.168.1.15) for bypassing MDR block"
        echo "  remove [IP] - Remove alias IP after demo"
        echo "  status      - Show current IPs"
        echo ""
        echo "Examples:"
        echo "  $0 add                 # use default 192.168.1.15"
        echo "  $0 add 192.168.1.20    # use custom IP"
        echo "  $0 remove 192.168.1.20 # remove custom IP"
        ;;
esac
