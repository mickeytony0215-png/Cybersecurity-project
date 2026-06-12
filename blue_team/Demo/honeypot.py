#!/usr/bin/env python3
"""
honeypot.py - Fake SSH Honeypot (Simulation Drive)
"""
import socket
import threading
import argparse
import time
import os
import sys

SSH_BANNER = b"SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.4\r\n"

def trigger_mock_attack(log_path, verbose, ip, port, client_str):
    ts = time.strftime('%Y-%m-%d %H:%M:%S')
    if verbose:
        print(f'\033[91m[!] TRAP  {ts}  {ip}:{port}\033[0m')
    
    time.sleep(0.5)
    log_line = f"[{ts}] Attacker IP: {ip} Port: {port} Data: {client_str}\n"

    try:
        with open(log_path, 'a') as f:
            f.write(log_line)
    except OSError as e:
        print(f'[!] Failed to write trap.log: {e}')

    if verbose:
        print(f'    Logged: {ip} → {log_path}')
        if client_str:
            print(f'    Client sent: {client_str[:80]}')
    print()

def main():
    # 強制定位於當前工作目錄，消滅層級錯位
    _default_log = os.path.join(os.getcwd(), 'trap.log')

    ap = argparse.ArgumentParser(description='Fake SSH Honeypot')
    ap.add_argument('--port', type=int, default=2222, help='Listen port (default 2222)')
    ap.add_argument('--host', default='0.0.0.0', help='Bind address (default 0.0.0.0)')
    ap.add_argument('--log', default=_default_log, help=f'Log file path (default {_default_log})')
    ap.add_argument('--quiet', action='store_true', help='Suppress console output')
    args = ap.parse_args()

    verbose = not args.quiet

    print(f"\033[93m{'='*55}")
    print(f"  Honeypot (Fake SSH) | {args.host}:{args.port}")
    print(f"  Banner: {SSH_BANNER.decode().strip()}")
    print(f"  Log:    {os.path.abspath(args.log)}")
    print(f"{'='*55}\033[0m")
    print("[*] Waiting for connections...\n")

    # (其餘程式碼完全相同，僅 main() 的觸發節奏優化如下)
    try:
        # 優化人類動作節奏：啟動後延遲 2.0 秒觸發第一波攻擊，模擬切換視窗按 Enter 的時間
        time.sleep(2.0)
        trigger_mock_attack(args.log, verbose, "192.168.43.10", 54321, "SSH-2.0-Go-OpenSSH-Client")
        
        # 5秒後觸發第二波攻擊
        time.sleep(5.0)
        trigger_mock_attack(args.log, verbose, "10.0.0.88", 61234, "Nmap NSE SSH-Brute")
        
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print('\n[*] Honeypot stopped.')

if __name__ == '__main__':
    main()