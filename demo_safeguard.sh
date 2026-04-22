#!/usr/bin/env bash
# ============================================================
# demo_safeguard.sh - Attacker Machine Protection
#
# Protects the attacker machine (your lab computer) during
# the attack-defense demo by:
#   1. Snapshotting system state BEFORE the demo
#   2. Restoring system state AFTER the demo
#   3. Marking this machine's role to block blue team tools
#
# Usage:
#   bash demo_safeguard.sh init-role         # one-time: mark as attacker
#   sudo bash demo_safeguard.sh snapshot     # before each demo
#   sudo bash demo_safeguard.sh restore      # after each demo
#   bash demo_safeguard.sh status            # show current state
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAFEGUARD_DIR="$SCRIPT_DIR/.safeguard"
SNAPSHOT_DIR="$SAFEGUARD_DIR/snapshot"
ROLE_FILE="$SCRIPT_DIR/.machine_role"

# ── init-role ───────────────────────────────────────────────
do_init_role() {
    echo "attacker" > "$ROLE_FILE"
    echo "[+] Machine role set to: attacker"
    echo "    File: $ROLE_FILE"
    echo ""
    echo "    Blue team scripts (eBPF MDR, network MDR) will now"
    echo "    REFUSE to run on this machine unless --force is used."
}

# ── snapshot ────────────────────────────────────────────────
do_snapshot() {
    if [[ $EUID -ne 0 ]]; then
        echo "[!] snapshot requires root. Run with: sudo"
        exit 1
    fi

    mkdir -p "$SNAPSHOT_DIR"

    echo "[*] Creating system state snapshot..."
    echo ""

    # 1. iptables
    iptables-save > "$SNAPSHOT_DIR/iptables.rules" 2>/dev/null || true
    rule_count=$(iptables -L INPUT -n 2>/dev/null | grep -c "DROP" || echo 0)
    echo "  [1/4] iptables rules saved ($rule_count DROP rules in INPUT)"

    # 2. crontab
    crontab -l > "$SNAPSHOT_DIR/crontab.bak" 2>/dev/null || echo -n > "$SNAPSHOT_DIR/crontab.bak"
    cron_count=$(wc -l < "$SNAPSHOT_DIR/crontab.bak" | tr -d ' ')
    echo "  [2/4] crontab saved ($cron_count entries)"

    # 3. network interfaces
    ip -4 addr show > "$SNAPSHOT_DIR/network_interfaces.txt" 2>/dev/null
    ip_count=$(ip -4 addr show | grep -c "inet " || echo 0)
    echo "  [3/4] network interfaces saved ($ip_count IPv4 addresses)"

    # 4. running processes (reference only, not restored)
    ps aux --sort=-%mem > "$SNAPSHOT_DIR/processes.txt" 2>/dev/null
    proc_count=$(wc -l < "$SNAPSHOT_DIR/processes.txt" | tr -d ' ')
    echo "  [4/4] process list saved ($proc_count processes)"

    date '+%Y-%m-%d %H:%M:%S' > "$SNAPSHOT_DIR/timestamp"

    echo ""
    echo "[+] Snapshot saved to: $SNAPSHOT_DIR"
    echo "    After demo, run: sudo bash demo_safeguard.sh restore"
}

# ── restore ─────────────────────────────────────────────────
do_restore() {
    if [[ $EUID -ne 0 ]]; then
        echo "[!] restore requires root. Run with: sudo"
        exit 1
    fi

    if [[ ! -d "$SNAPSHOT_DIR" ]]; then
        echo "[!] No snapshot found. Run 'sudo bash demo_safeguard.sh snapshot' first."
        exit 1
    fi

    ts=$(cat "$SNAPSHOT_DIR/timestamp" 2>/dev/null || echo "unknown")
    echo "[*] Restoring from snapshot (taken: $ts)..."
    echo ""

    # 1. Stop demo processes (graceful then force)
    echo "  [1/4] Stopping demo processes..."
    FOUND=""
    for proc in target_app.py honeypot.py blue_ebpf_mdr.py blue_ebpf_mdr_v2.py \
                blue_mdr_network.py soc_dashboard.py red_attacker.py \
                red_reverse_shell.py exfil_listener.py exfil_agent.py; do
        pids=$(pgrep -f "$proc" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            echo "    SIGTERM $proc (PID $pids)"
            kill -15 $pids 2>/dev/null || true
            FOUND="$FOUND $pids"
        fi
    done
    memfd_pids=$(ls -la /proc/[0-9]*/exe 2>/dev/null | grep 'memfd:' | awk -F/ '{print $3}' || true)
    if [[ -n "$memfd_pids" ]]; then
        for pid in $memfd_pids; do
            echo "    SIGTERM memfd PID=$pid"
            kill -15 "$pid" 2>/dev/null || true
            FOUND="$FOUND $pid"
        done
    fi
    if [[ -n "$FOUND" ]]; then
        sleep 2
        for pid in $FOUND; do
            if kill -0 "$pid" 2>/dev/null; then
                echo "    SIGKILL PID=$pid (did not exit)"
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
    fi
    echo "    Done."

    # 2. Restore iptables
    echo "  [2/4] Restoring iptables rules..."
    if [[ -f "$SNAPSHOT_DIR/iptables.rules" ]]; then
        iptables-restore < "$SNAPSHOT_DIR/iptables.rules" 2>/dev/null && \
            echo "    Restored from snapshot." || {
            echo "    [!] Restore failed, flushing demo DROP rules instead..."
            iptables -L INPUT -n --line-numbers 2>/dev/null | grep "DROP" | \
                awk '{print $1}' | sort -rn | while read num; do
                iptables -D INPUT "$num" 2>/dev/null || true
            done
            echo "    Flushed DROP rules."
        }
    else
        echo "    No iptables snapshot, skipping."
    fi

    # 3. Restore crontab
    echo "  [3/4] Restoring crontab..."
    if [[ -f "$SNAPSHOT_DIR/crontab.bak" ]]; then
        if [[ -s "$SNAPSHOT_DIR/crontab.bak" ]]; then
            crontab "$SNAPSHOT_DIR/crontab.bak" 2>/dev/null && \
                echo "    Restored $(wc -l < "$SNAPSHOT_DIR/crontab.bak" | tr -d ' ') entries." || \
                echo "    [!] crontab restore failed."
        else
            crontab -r 2>/dev/null || true
            echo "    Snapshot had empty crontab, cleared."
        fi
    else
        echo "    No crontab snapshot, skipping."
    fi

    # 4. Remove IP aliases added during demo
    echo "  [4/4] Removing demo IP aliases..."
    STATE_FILE="$SCRIPT_DIR/red_team/.alias_ip_state"
    if [[ -f "$STATE_FILE" ]]; then
        ALIAS_CIDR=$(sed -n 1p "$STATE_FILE")
        INTERFACE=$(sed -n 2p "$STATE_FILE")
        ALIAS_IP=$(echo "$ALIAS_CIDR" | cut -d/ -f1)
        if ip addr show "$INTERFACE" 2>/dev/null | grep -q "$ALIAS_IP"; then
            echo "    Removing alias $ALIAS_IP from $INTERFACE"
            ip addr del "$ALIAS_CIDR" dev "$INTERFACE" 2>/dev/null || true
        fi
        rm -f "$STATE_FILE"
        echo "    Done."
    else
        echo "    No alias state found (clean)."
    fi

    echo ""
    echo "[+] System state restored to pre-demo snapshot."
    echo "    Verify: sudo bash demo_safeguard.sh status"
}

# ── status ──────────────────────────────────────────────────
do_status() {
    echo "[*] System State Report"
    echo ""

    # Machine role
    if [[ -f "$ROLE_FILE" ]]; then
        role=$(cat "$ROLE_FILE" | tr -d '[:space:]')
        echo "  Machine role : $role"
    else
        echo "  Machine role : NOT SET (run: bash demo_safeguard.sh init-role)"
    fi

    # Snapshot
    if [[ -d "$SNAPSHOT_DIR" ]]; then
        ts=$(cat "$SNAPSHOT_DIR/timestamp" 2>/dev/null || echo "unknown")
        echo "  Snapshot     : $ts"
    else
        echo "  Snapshot     : NONE"
    fi
    echo ""

    # iptables
    if [[ $EUID -eq 0 ]]; then
        drop_count=$(iptables -L INPUT -n 2>/dev/null | grep -c "DROP" || echo 0)
        if [[ "$drop_count" -gt 0 ]]; then
            echo "  iptables     : $drop_count DROP rules in INPUT"
            iptables -L INPUT -n 2>/dev/null | grep "DROP" | while read line; do
                echo "                 $line"
            done
        else
            echo "  iptables     : clean (no DROP rules)"
        fi
    else
        echo "  iptables     : (need sudo to check)"
    fi

    # IP alias
    STATE_FILE="$SCRIPT_DIR/red_team/.alias_ip_state"
    if [[ -f "$STATE_FILE" ]]; then
        alias_ip=$(sed -n 1p "$STATE_FILE" | cut -d/ -f1)
        iface=$(sed -n 2p "$STATE_FILE")
        echo "  IP alias     : $alias_ip on $iface (ACTIVE)"
    else
        echo "  IP alias     : none"
    fi

    # Demo processes
    echo ""
    found=false
    for proc in target_app.py honeypot.py blue_ebpf_mdr.py blue_ebpf_mdr_v2.py \
                blue_mdr_network.py red_attacker.py red_reverse_shell.py exfil_listener.py; do
        pids=$(pgrep -f "$proc" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            if ! $found; then
                echo "  Demo processes:"
                found=true
            fi
            echo "    $proc (PID $pids)"
        fi
    done
    if ! $found; then
        echo "  Demo processes: none running"
    fi
}

# ── main ────────────────────────────────────────────────────
case "${1:-}" in
    snapshot)   do_snapshot ;;
    restore)    do_restore ;;
    status)     do_status ;;
    init-role)  do_init_role ;;
    *)
        echo "Usage: demo_safeguard.sh {snapshot|restore|status|init-role}"
        echo ""
        echo "  init-role  Mark this machine as 'attacker' (blocks blue team tools)"
        echo "  snapshot   Save system state before demo (requires sudo)"
        echo "  restore    Restore system state after demo (requires sudo)"
        echo "  status     Show current state vs snapshot"
        echo ""
        echo "  Workflow:"
        echo "    1. bash demo_safeguard.sh init-role       # one-time"
        echo "    2. sudo bash demo_safeguard.sh snapshot   # before demo"
        echo "    3. ... run demo ..."
        echo "    4. sudo bash demo_safeguard.sh restore    # after demo"
        ;;
esac
