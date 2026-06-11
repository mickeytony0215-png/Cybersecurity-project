# Blue Team Defense — 10-Minute Presentation Outline

**Source:** `docs/BLUE_TEAM_REPORT.tex` (Group 6, Blue Team)
**Duration:** 10:00 · **Format:** bullets on slides + spoken script + screenshots
**Emphasis:** honeypot and eBPF — code and functionality
**Narrative arc (起承轉合):** Setup → Development → Turn → Resolution

> Slide text and speaker script are both in English. "Screenshot / Visual" tells you
> exactly what to capture (code lines or a report figure).

---

## Pacing table (total 10:00)

| # | Slide | Act | Time | Cumulative |
|---|---|---|---|---|
| 0 | Title | — | 0:15 | 0:15 |
| 1 | The defender's problem | **Setup (起)** | 1:00 | 1:15 |
| 2 | Defense-in-depth model | **Setup (起)** | 0:45 | 2:00 |
| 3 | Honeypot deception (code) | **Development (承)** | 1:15 | 3:15 |
| 4 | Network MDR auto-block (code) | **Development (承)** | 0:45 | 4:00 |
| 5 | Why eBPF | **Development (承)** | 0:45 | 4:45 |
| 6 | eBPF: hunting the fileless chain (code) | **Development (承)** | 1:30 | 6:15 |
| 7 | eBPF: reverse-shell detection + kernel kill (code) | **Development — climax (承)** | 1:30 | 7:45 |
| 8 | Where the defense fails | **Turn (轉)** | 1:15 | 9:00 |
| 9 | Lessons & hardening | **Resolution (合)** | 0:45 | 9:45 |
| 10 | Closing | **Resolution (合)** | 0:15 | 10:00 |

> Core slides S3–S7 (~5.75 min) are all honeypot + eBPF — the requested focus.

---

## S0 — Title (0:15)

**Slide**
- **Blue Team Defense — Behavior-based Detection & Kernel Response**
- Group 6 · members · date

**Speaker script**
> "Our attack report already broke into the target end-to-end. Today I take the
> defender's seat and show how we detect and respond to each of those behaviors."

---

## S1 — Setup (起): The defender's problem (1:00)

**Slide**
- Attacker kill chain: `recon → SSTI → fileless ICMP C2 → exfil` (runs as **root**)
- The entry point (SSTI) is already lost → defense is **not "block the door"**, it is **watch behavior and respond in real time**
- Two principles: **Behavior over signature** · **Defense in depth**

**Speaker script**
> "The attacker has root, and the payload is *fileless* — nothing on disk to scan,
> and one source-IP change defeats any IP block. So we don't bet on a single wall.
> We bet on layering, and on watching *what a process does*, not who it is."

**Screenshot / Visual**
- Report §2.1 "attacker behaviors" list, or the red-team report §4 kill-chain table
  (`Recon → … → Exfiltration`).

---

## S2 — Setup (起): Defense-in-depth model (0:45)

**Slide**
- **Layer 1 — Network:** honeypot + `iptables` MDR → blocks **source IPs** (reactive, bypassable)
- **Layer 2 — Kernel (eBPF):** syscall hooks + kernel kill → blocks **behavior**, source-IP-agnostic
- **SOC dashboard:** monitoring plane (watch only, no enforcement)

**Speaker script**
> "Ordering matters. Layer 1 is cheap, gives the earliest signal, but is trivially
> bypassed. Layer 2 is the real enforcement point — it acts on behavior the attacker
> can't avoid if they want code execution and a control channel."

**Screenshot / Visual**
- Report **Figure "Defense-in-depth"** (§2.2 — the three-band + SOC TikZ diagram).

---

## S3 — Development (承): Honeypot deception (1:15)

**Slide**
- Fake SSH: banner is byte-for-byte a real OpenSSH version string → indistinguishable to `nmap -sV`
- **Near-zero false positive:** nothing legitimate connects to :2222 → any hit is suspicious
- Every hit appended to `trap.log` (IP / port / first 100 bytes) — the contract with the MDR

**Speaker script**
> "The honeypot's value is clean signal: high confidence, low noise. We answer with a
> version string identical to real OpenSSH, so a scanner is drawn in — and anything that
> connects gets logged to trap.log with its IP."

**Screenshot / Visual** — code: `target/honeypot.py`
- **L30–36** — `SSH_BANNER` / `FAKE_RESPONSE`
- **L50–78** — send banner + write the `trap.log` line

---

## S4 — Development (承): Network MDR auto-block (0:45)

**Slide**
- Tails `trap.log`; on a new IP runs `iptables -I INPUT 1 -s <ip> -j DROP`
- Insert at position 1 = highest priority → cuts the IP off **all** ports in < 1 s
- Fatal weakness: it blocks the **source IP**, and the source IP is attacker-controlled

**Speaker script**
> "A new IP shows up, and in under a second we insert a top-priority DROP across every
> port. But that's also its undoing — it blocks the source IP, and on the next slide the
> attacker defeats it with a single alias." *(plants the seed for the Turn)*

**Screenshot / Visual** — code: `blue_team/blue_mdr_network.py`
- **L47–52** — `block_ip()` (the `iptables` command)
- **L87–119** — watcher: `seek` to end of file, extract new IPs, call block

---

## S5 — Development (承): Why eBPF (0:45)

**Slide**
- **Source-IP-agnostic** — acts on behavior; Layer-1's IP bypass is irrelevant here
- **Fileless-visible** — sees `memfd_create` / `execve` arguments directly
- **Pre-syscall enforcement** — hooks fire at `sys_enter_*`, *before* the action completes
- **Low overhead** — JIT-compiled to native code, O(1) hash-map lookups

**Speaker script**
> "eBPF lets us run a kernel-verified program inside the kernel, attached to syscall
> entry points. It ignores IPs and file hashes — it only sees what a process is doing,
> and it can kill it *before* the dangerous action actually happens."

**Screenshot / Visual**
- Report **Figure "eBPF pipeline"** (C → BCC → bytecode → verifier → JIT → tracepoint → perf buffer).

---

## S6 — Development (承): Hunting the fileless chain (1:30)

**Slide**
- Hook 1 `memfd_create` → **alert only** (taint the process; don't kill — it has benign uses)
- Hook 0 `fork` → propagate the taint to children (one fork shouldn't shake off tracking)
- Hook 2 `execve` → argv points at `/proc/<pid>/fd/<N>` = fileless loader → **kill**
- Hook 3 raw ICMP socket → alone it only alerts; **correlated with memfd → kill**
- Design: enforce only on the **highest-confidence** signal

**Speaker script**
> "Fileless staging means memfd creates an in-memory file, then `/proc/fd` executes it.
> We don't kill on memfd — it has legitimate users. We kill at `execve` when we see the
> `/proc/fd` pattern in argv, and we keep a memfd+raw-ICMP correlation as a backstop."

**Screenshot / Visual** — code: `blue_team/blue_ebpf_mdr_v2.py`
- **L106–116** — memfd hook (`__KILL_MEMFD__` is empty = alert-only)
- **L149–178** — `execve` argv `/proc/fd` check → `__KILL_EXEC__`
- **L196–211** — raw ICMP + correlation → `__KILL_ICMP_CORR__`

---

## S7 — Development climax (承): Reverse-shell detection + kernel kill (1:30)

**Slide**
- A pure TCP reverse shell uses only ordinary syscalls (`socket → connect → dup2 → pty`) → the four hooks above stay silent
- Hooks 5/6 `dup2`/`dup3`: per-PID bitmask — stdin/stdout/stderr each set one bit
- All three redirected to the same socket → mask `0x07` → **confirmed reverse shell → SIGKILL**
- Port-agnostic (catches it even on 80/443); `dup3` hooked too (`inheritable=False` calls dup3)
- Kill = `bpf_send_signal(9)`, in-kernel, *before* the syscall completes (no userspace race)

**Speaker script**
> "A reverse shell wires stdin, stdout and stderr to one socket. We track that as a
> bitmask — the moment all three bits hit `0x07`, we fire `bpf_send_signal` and kill it,
> before the syscall even completes, and regardless of which port it used."

**Screenshot / Visual**
- **Figure:** report **"Reverse-shell bitmask state machine"** (`000 → 001 → 011 → 111 → SIGKILL`) — best climax visual
- **Code:** `blue_team/blue_ebpf_mdr_v2.py`
  - **L279–300** — `dup2` bitmask → `0x07` kill
  - **L454–457** — load-time injection: `__KILL_*__` replaced with `e.killed = 1; bpf_send_signal(9);` (one C source, two behaviors: monitor vs `--kill`)

---

## S8 — Turn (轉): Where the defense fails (1:15)

**Slide**
- **IP block is bypassed** — add an alias IP and you have a fresh identity (NAT/proxy generalize this)
- **eBPF is blind to malice via legitimate syscalls** — DNS exfil uses only `socket(SOCK_DGRAM)+sendto` to :53 → no hook fires
- **Persistence is untouched** — a planted `crontab` re-downloads the agent; killing a process doesn't remove its launcher
- **The detector is itself a risk** — a misclassified `bpf_send_signal(9)` is a self-inflicted DoS
- **Root cause remains** — SSTI + running as root are never fixed

**Speaker script**
> "Here's the honest part. We're strong, but three things walk through the whole stack:
> an IP swap defeats Layer 1, exfil built from *good* syscalls is invisible to eBPF, and
> cron persistence survives every kill. And one false positive turns our own detector
> into the outage."

**Screenshot / Visual**
- Report **Table 2** — the `Gap` rows (T1190 / T1048.003 / T1053.003), or the **"attack-defense rounds"** figure with its red gap boxes.

---

## S9 — Resolution (合): Lessons & hardening (0:45)

**Slide**
- Enumerating "bad" syscalls is blind to malice in "good" ones → add a **different sensor** (egress / DNS analytics)
- Persistence needs **eradication** (watch cron/systemd/rc files), not just process kills
- Move from single-signal kills to **scoring** (correlate connect + dup2 + new-socket) → auto-kill only on high scores, else quarantine
- Fix the **root cause** — patch the SSTI, drop root, add a WAF so Layer 2 is a backstop, not the only wall

**Speaker script**
> "Every gap has an answer: exfil needs a DNS-analytics sensor, not a syscall hook;
> persistence needs eradication; auto-kill should be score-gated to cut false positives;
> and above all, fix the SSTI and drop root so the kernel layer is a backstop, not the
> last line of defense."

---

## S10 — Resolution (合): Closing (0:15)

**Slide**
- **Defense-in-depth is a continuous process, not a finished product.**
- Each layer is expected to fail against some class of attack → security is making sure the **next layer / next sensor is already watching the gap**

**Speaker script**
> "The takeaway is one line: defense-in-depth is a continuous process, not a finished
> product. Every layer gets bypassed by something — what matters is whether the next one
> is already watching that gap."

**Screenshot / Visual (optional)**
- Report **"attack-defense rounds"** figure (green / amber / red) as a full-picture closer.

---

## Asset checklist

**Code screenshots**
| Slide | File | Lines | What it shows |
|---|---|---|---|
| S3 | `target/honeypot.py` | 30–36 | fake SSH banner / fake rejection |
| S3 | `target/honeypot.py` | 50–78 | send banner + write `trap.log` |
| S4 | `blue_team/blue_mdr_network.py` | 47–52 | `iptables -I INPUT 1 ... DROP` |
| S4 | `blue_team/blue_mdr_network.py` | 87–119 | tail `trap.log`, block new IPs |
| S6 | `blue_team/blue_ebpf_mdr_v2.py` | 106–116 | memfd hook (alert-only / taint) |
| S6 | `blue_team/blue_ebpf_mdr_v2.py` | 149–178 | `execve` argv `/proc/fd` → kill |
| S6 | `blue_team/blue_ebpf_mdr_v2.py` | 196–211 | raw ICMP + correlation → kill |
| S7 | `blue_team/blue_ebpf_mdr_v2.py` | 279–300 | `dup2` bitmask → `0x07` kill |
| S7 | `blue_team/blue_ebpf_mdr_v2.py` | 454–457 | load-time `bpf_send_signal(9)` injection |

**Report figures / tables** (from `BLUE_TEAM_REPORT.pdf`)
| Slide | Asset | Section |
|---|---|---|
| S2 | Figure "Defense-in-depth" | §2.2 |
| S5 | Figure "eBPF pipeline" | §"Why eBPF" |
| S7 | Figure "Reverse-shell bitmask state machine" | §"Reverse-shell detection" |
| S8 | Table 2 "Detection coverage" (Gap rows) | §2.3 |
| S8 / S10 | Figure "attack-defense rounds" | §"Detection-and-Response Workflow" |

**Optional live-evidence screenshots** (red-team report or your own re-run)
- Honeypot trap fired · IP-alias bypass · C2 beacon established · exfil loot reassembled
- Or your SOC dashboard / `trap.log` / a kill event from `soc_events.jsonl`
