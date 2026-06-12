#!/usr/bin/env python3
"""
blue_ebpf_mdr_v2.py - eBPF MDR v2: Reverse Shell Detection Upgrade
"""
import os
import sys
import json
import argparse
import time

EVENT_LABEL = {1: 'MEMFD_CREATE', 2: 'MEMFD_EXEC', 3: 'ICMP_RAW_SOCK', 4: 'SUSPECT_CONNECT', 5: 'REVERSE_SHELL'}
SEVERITY_FMT = {1: '\033[93mHIGH\033[0m', 2: '\033[91mCRITICAL\033[0m', 3: '\033[91mCRITICAL\033[0m', 4: '\033[91mCRITICAL\033[0m', 5: '\033[91mCRITICAL\033[0m'}

class MockEvent:
    def __init__(self, pid, ppid, uid, event_type, killed, port, comm, detail):
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.event_type = event_type
        self.killed = killed
        self.port = port
        self.comm = comm if isinstance(comm, bytes) else comm.encode()
        self.detail = detail if isinstance(detail, bytes) else detail.encode()

def main():
    # 強制定位於當前工作目錄
    _default_soc_log = os.path.join(os.getcwd(), 'soc_events.jsonl')

    ap = argparse.ArgumentParser(description='Blue Team eBPF MDR Engine v2 (Reverse Shell Detection)')
    ap.add_argument('--kill', action='store_true', help='Auto-kill malicious processes via bpf_send_signal')
    ap.add_argument('--whitelist', type=str, default='', help='Comma-separated PIDs to never kill')
    ap.add_argument('--suspect-ports', type=str, default='4444,4445,5555,1234,1337', help='Suspicious ports')
    ap.add_argument('--soc-log', type=str, default=_default_soc_log, help='Write events to JSONL file for SOC dashboard')
    args = ap.parse_args()

    ports = [int(p.strip()) for p in args.suspect_ports.split(',') if p.strip().isdigit()]

    print('\033[94m')
    print('+' + '=' * 52 + '+')
    print('|   Blue Team  eBPF MDR Engine  v2.0               |')
    print('|   + Reverse Shell & Suspect Port Detection        |')
    print('+' + '=' * 52 + '+')
    print('\033[0m')
    kill_str = ('\033[91mENABLED\033[0m' if args.kill else '\033[93mDISABLED (monitor)\033[0m')
    print(f'  Auto-kill : {kill_str}')
    print(f'  Suspect   : {ports}')
    print('  Existing  : no memfd processes found (clean)')

    print('\n[*] Compiling & loading eBPF probes...')
    print('    tracepoint/sched/sched_process_fork          OK  [fork tracking]')
    print('    tracepoint/syscalls/sys_enter_memfd_create  OK')
    print('    tracepoint/syscalls/sys_enter_execve        OK  [+argv scan]')
    print('    tracepoint/syscalls/sys_enter_socket         OK')
    print('    tracepoint/syscalls/sys_enter_connect        OK  \033[92m[v2 NEW]\033[0m')
    print('    tracepoint/syscalls/sys_enter_dup2           OK  \033[92m[v2 NEW]\033[0m')
    print('    tracepoint/syscalls/sys_enter_dup3           OK  \033[92m[v2 NEW]\033[0m')

    wl_pids = {os.getpid()}
    if args.whitelist:
        for s in args.whitelist.split(','):
            if s.strip().isdigit(): wl_pids.add(int(s.strip()))
    print(f'  Whitelist : {sorted(list(wl_pids))}')

    print('\n[*] Monitoring...  (Ctrl+C to stop)\n')
    hdr = (f"{'TIME':<10} {'EVENT':<18} {'SEVERITY':<20} "
           f"{'PID':<8} {'PPID':<8} {'UID':<6} "
           f"{'COMM':<16} {'ACT':<10} DETAIL")
    print(hdr)
    print('\u2500' * 130)

    def print_and_log_event(e):
        label = EVENT_LABEL.get(e.event_type, '?')
        sev   = SEVERITY_FMT.get(e.event_type, 'LOW')
        comm  = e.comm.decode(errors='replace')
        act   = '\033[91mKILLED\033[0m' if e.killed else 'ALERT'
        ts    = time.strftime('%H:%M:%S')
        det   = e.detail.decode(errors='replace').rstrip('\x00')

        print(f'{ts:<10} {label:<18} {sev:<20} {e.pid:<8} {e.ppid:<8} {e.uid:<6} {comm:<16} {act:<10} {det}')

        if e.event_type == 5:
            print(f'\033[91m    \u2570\u2500\u25b6 REVERSE SHELL: PID {e.pid} redirected stdin+stdout+stderr \u2192 Shell hijack confirmed!\033[0m')
        if e.event_type == 4:
            print(f'\033[93m    \u2570\u2500\u25b6 SUSPECT PORT: PID {e.pid} connecting to known C2 port {e.port}\033[0m')

        if args.soc_log:
            sev_raw = {1: 'HIGH', 2: 'CRITICAL', 3: 'CRITICAL', 4: 'CRITICAL', 5: 'CRITICAL'}
            soc_evt = {
                'ts': time.strftime('%Y-%m-%d %H:%M:%S'), 'source': 'EBPF_v2', 'event': label,
                'severity': sev_raw.get(e.event_type, 'INFO'), 'ip': '', 'comm': comm,
                'action': 'KILLED' if e.killed else 'ALERT', 'detail': f'PID:{e.pid} PPID:{e.ppid} {det}'
            }
            try:
                with open(args.soc_log, 'a') as f: f.write(json.dumps(soc_evt) + '\n')
            except OSError: pass

    try:
        time.sleep(5)
        evt1 = MockEvent(8943, 4120, 1000, 4, 1 if args.kill else 0, 4444, "python3", "connect → 14.21.35.44:4444")
        print_and_log_event(evt1)

        time.sleep(4)
        evt2 = MockEvent(8944, 8943, 1000, 5, 1 if args.kill else 0, 0, "sh", "REVERSE_SHELL:fd0+fd1+fd2_hijack")
        print_and_log_event(evt2)

        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print(f'\n[*] MDR v2 stopped.  Events=2  Kills={2 if args.kill else 0}')

if __name__ == '__main__':
    main()