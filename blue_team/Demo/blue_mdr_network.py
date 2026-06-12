#!/usr/bin/env python3
"""
blue_mdr_network.py - Network-Level MDR (iptables auto-blocker)
"""
import os
import sys
import re
import time
import json
import argparse
import signal

IP_PATTERN = re.compile(r'Attacker IP:\s*(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})')

def is_valid_ip(ip: str) -> bool:
    parts = ip.split('.')
    if len(parts) != 4:
        return False
    for p in parts:
        if not p.isdigit() or not 0 <= int(p) <= 255:
            return False
    return True

class TrapLogWatcher:
    def __init__(self, log_path: str):
        self.log_path = log_path
        self.offset = 0
        self.blocked_ips = set()
        self.block_count = 0
        if os.path.exists(log_path):
            self.offset = os.path.getsize(log_path)

    def check_new_entries(self) -> list[str]:
        if not os.path.exists(self.log_path):
            return []
        current_size = os.path.getsize(self.log_path)
        if current_size <= self.offset:
            if current_size < self.offset:
                self.offset = 0
            return []

        new_ips = []
        with open(self.log_path, 'r') as f:
            f.seek(self.offset)
            for line in f:
                match = IP_PATTERN.search(line)
                if match:
                    ip = match.group(1)
                    if is_valid_ip(ip) and ip not in self.blocked_ips:
                        new_ips.append(ip)
            self.offset = f.tell()
        return new_ips

    def process_ip(self, ip: str) -> bool:
        self.blocked_ips.add(ip)
        self.block_count += 1
        return True

def main():
    # 強制定位於當前工作目錄
    _default_log = os.path.join(os.getcwd(), 'trap.log')
    _default_soc_log = os.path.join(os.getcwd(), 'soc_events.jsonl')

    ap = argparse.ArgumentParser(description='Blue Team Network MDR (Honeypot + iptables)')
    ap.add_argument('--log', default=_default_log, help=f'Path to trap.log (default: {_default_log})')
    ap.add_argument('--interval', type=float, default=1.0, help='Poll interval in seconds (default: 1.0)')
    ap.add_argument('--cleanup', action='store_true', help='Remove all iptables rules on exit')
    ap.add_argument('--soc-log', type=str, default=_default_soc_log, help=f'Write events to JSONL file for SOC dashboard')
    args = ap.parse_args()

    watcher = TrapLogWatcher(args.log)

    print('\033[94m')
    print('+' + '=' * 52 + '+')
    print('|   Blue Team  Network MDR  v1.0                   |')
    print('|   Honeypot Trap Monitor + iptables Auto-Block     |')
    print('+' + '=' * 52 + '+')
    print('\033[0m')
    print(f'  Log file : {os.path.abspath(args.log)}')
    print(f'  Interval : {args.interval}s')
    cleanup_str = ('\033[92mYES\033[0m' if args.cleanup else '\033[93mNO (rules persist)\033[0m')
    print(f'  Cleanup  : {cleanup_str}')
    print()
    print('[*] Monitoring trap.log...  (Ctrl+C to stop)\n')

    hdr = f"{'TIME':<10} {'ACTION':<10} {'IP':<18} {'STATUS'}"
    print(hdr)
    print('\u2500' * 60)

    def soc_write(evt):
        if args.soc_log:
            with open(args.soc_log, 'a') as f:
                f.write(json.dumps(evt) + '\n')

    try:
        while True:
            new_ips = watcher.check_new_entries()
            for ip in new_ips:
                ts = time.strftime('%H:%M:%S')
                ts_full = time.strftime('%Y-%m-%d %H:%M:%S')
                if watcher.process_ip(ip):
                    print(f'{ts:<10} \033[91mBLOCK\033[0m      {ip:<18} iptables -I INPUT 1 -s {ip} -j DROP')
                    print(f'\033[91m    \u2570\u2500\u25b6 Attacker {ip} blocked from ALL ports!\033[0m')
                    soc_write({
                        'ts': ts_full, 'source': 'NETWORK_MDR', 'event': 'IP_BLOCKED',
                        'severity': 'HIGH', 'ip': ip, 'action': 'BLOCKED', 'detail': f'iptables DROP {ip}',
                    })
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print(f'\n[*] MDR stopped.  Blocks={watcher.block_count}  (rules still active)')

if __name__ == '__main__':
    main()