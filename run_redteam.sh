#!/usr/bin/env bash
# ============================================================
# run_redteam.sh - Red Team Isolated Container
#
# Runs all red team tools inside a Docker container.
# Host is protected: filesystem, processes, crontab are isolated.
# Network is shared (--net=host) for ICMP C2 and LAN scanning.
#
# What IS isolated:
#   - Filesystem: cleanup.sh / rm -rf only affects container
#   - Processes:  kill -9 only affects container processes
#   - Crontab:    container has no crontab to destroy
#   - Packages:   no eBPF/BCC installed, blue team scripts won't work
#
# What is NOT isolated (shared with host, required for demo):
#   - Network stack: ip addr, iptables commands affect host
#     (ip_switch.sh needs real alias IPs on the LAN)
#
# Usage:
#   bash run_redteam.sh              # start T3 shell
#   bash run_redteam.sh exec         # open T4 shell (second terminal)
#   bash run_redteam.sh stop         # stop + remove container
#   bash run_redteam.sh build        # rebuild image
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="redteam-isolated"
CONTAINER="redteam"

do_build() {
    echo "[*] Building red team container image..."
    docker build -t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile.redteam" "$SCRIPT_DIR"
    echo "[+] Done: $IMAGE"
}

ensure_image() {
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        echo "[*] Image not found, building..."
        do_build
    fi
}

do_run() {
    ensure_image

    if docker ps -q -f name="^${CONTAINER}$" 2>/dev/null | grep -q .; then
        echo "[!] Container already running."
        echo "    T4 shell : bash run_redteam.sh exec"
        echo "    Stop     : bash run_redteam.sh stop"
        exit 1
    fi

    docker rm "$CONTAINER" 2>/dev/null || true

    echo "[*] Starting red team container"
    echo "    Image     : $IMAGE (Ubuntu 22.04)"
    echo "    Network   : host"
    echo "    Isolation : filesystem, processes, crontab"
    echo ""
    echo "    Second terminal (T4): bash run_redteam.sh exec"
    echo "    Stop container:       bash run_redteam.sh stop"
    echo ""
    echo "============================================================"

    docker run -it \
        --name "$CONTAINER" \
        --network=host \
        --cap-add=NET_RAW \
        --cap-add=NET_ADMIN \
        --hostname redteam \
        -v "$SCRIPT_DIR/red_team:/workspace/red_team" \
        -v "$SCRIPT_DIR/loot:/workspace/loot" \
        -v "$SCRIPT_DIR/target:/workspace/target:ro" \
        "$IMAGE" bash
}

do_exec() {
    if ! docker ps -q -f name="^${CONTAINER}$" 2>/dev/null | grep -q .; then
        echo "[!] Container not running. Start with: bash run_redteam.sh"
        exit 1
    fi
    echo "[*] Attaching to running container ($CONTAINER)..."
    docker exec -it "$CONTAINER" bash
}

do_stop() {
    if docker ps -q -f name="^${CONTAINER}$" 2>/dev/null | grep -q .; then
        echo "[*] Stopping container..."
        docker stop "$CONTAINER" >/dev/null
    fi
    docker rm "$CONTAINER" 2>/dev/null || true
    echo "[+] Container removed. Host is clean."
}

case "${1:-run}" in
    build) do_build ;;
    run)   do_run ;;
    exec)  do_exec ;;
    stop)  do_stop ;;
    *)
        echo "Usage: run_redteam.sh {run|exec|stop|build}"
        echo ""
        echo "  run    Start red team shell (T3)"
        echo "  exec   Open T4 shell in running container"
        echo "  stop   Stop and remove container"
        echo "  build  Rebuild image"
        ;;
esac
