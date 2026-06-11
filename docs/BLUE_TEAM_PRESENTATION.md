# Blue Team Defense — 10-Minute Presentation Outline

**Source:** `docs/BLUE_TEAM_REPORT.tex` (Group 6, Blue Team)
**Duration:** 10:00 · **Format:** bullets on slides + spoken script + screenshots
**Emphasis:** honeypot and eBPF — code and functionality
**Narrative arc (起承轉合):** Setup → Development → Turn → Resolution

> 投影片文字維持英文；下方的「Speaker script（講稿）」為中文口語稿。
> 「Screenshot / Visual」標明該擷取的畫面（程式碼行數或報告圖表）。

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
> 「我們的攻擊報告已經把目標從頭到尾完整攻破。今天我換到防守方的位置，
> 示範我們如何偵測、並即時回應這些行為中的每一個。」

---

## S1 — Setup (起): The defender's problem (1:00)

**Slide**
- Attacker kill chain: `recon → SSTI → fileless ICMP C2 → exfil` (runs as **root**)
- The entry point (SSTI) is already lost → defense is **not "block the door"**, it is **watch behavior and respond in real time**
- Two principles: **Behavior over signature** · **Defense in depth**

**Speaker script**
> 「攻擊者已經拿到 root，而且 payload 是*無檔案（fileless）*的——磁碟上沒有東西
> 可以掃描，來源 IP 換一個就破解了任何 IP 封鎖。所以我們不把賭注押在單一道牆上，
> 而是押在分層防禦，以及監看*一個行程在做什麼*，而不是它是誰。」

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
> 「層次的順序很重要。第一層成本低、能給出最早的訊號，但很容易被繞過；
> 第二層才是真正的執法點——它針對的是攻擊者只要想執行程式碼、想要一條控制
> 通道，就無法避免的行為。」

**Screenshot / Visual**
- Report **Figure "Defense-in-depth"** (§2.2 — the three-band + SOC TikZ diagram).

---

## S3 — Development (承): Honeypot deception (1:15)

**Slide**
- Fake SSH: banner is byte-for-byte a real OpenSSH version string → indistinguishable to `nmap -sV`
- **Near-zero false positive:** nothing legitimate connects to :2222 → any hit is suspicious
- Every hit appended to `trap.log` (IP / port / first 100 bytes) — the contract with the MDR

**Speaker script**
> 「蜜罐的價值在於乾淨的訊號：高可信度、低雜訊。我們回應一個跟真實 OpenSSH
> 完全相同的版本字串，把掃描器引誘進來——任何連進來的東西，都會連同它的 IP
> 一起被記到 trap.log。」

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
> 「一個新 IP 出現，我們在不到一秒內就插入一條最高優先權、跨所有連接埠的 DROP
> 規則。但這也正是它的罩門——它封的是來源 IP，而下一張投影片裡，攻擊者只要加
> 一個別名 IP 就破解了。」*（為「轉折」埋下伏筆）*

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
> 「eBPF 讓我們在核心裡跑一支經過核心驗證的程式，掛在系統呼叫的進入點上。
> 它不看 IP、也不看檔案雜湊——它只看一個行程正在做什麼，而且可以在危險動作
> 真正發生*之前*，就把它殺掉。」

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
> 「無檔案的佈署手法是：memfd 先建立一個記憶體裡的檔案，再透過 `/proc/fd` 執行它。
> 我們不在 memfd 階段下手——它有合法用途。我們是在 `execve` 看到 argv 裡出現
> `/proc/fd` 這個樣式時才殺，並保留 memfd 加上 raw ICMP 的關聯偵測當作後備。」

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
> 「反向 shell 會把 stdin、stdout、stderr 三者都接到同一個 socket。我們用一個 bitmask
> 來追蹤——當三個位元同時湊滿 `0x07` 的那一刻，我們就觸發 `bpf_send_signal` 把它殺掉，
> 在系統呼叫還沒完成之前，而且不管它用的是哪個連接埠。」

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
> 「接下來是誠實的部分。我們很強，但有三件事能穿過整個防禦堆疊：換個 IP 就破解
> 第一層、用*良性*系統呼叫組成的外洩對 eBPF 完全隱形、而 cron 的常駐機制能熬過
> 每一次擊殺。而且只要一次誤判，我們自己的偵測器就會變成一場服務中斷。」

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
> 「每個缺口都有對策：外洩需要的是 DNS 流量分析感測器，而不是系統呼叫 hook；
> 常駐機制需要的是徹底根除；自動擊殺應該用分數門檻來把關，以降低誤判；而最重要
> 的是修掉 SSTI、卸掉 root 權限，讓核心層是一道後備防線，而不是最後一道防線。」

---

## S10 — Resolution (合): Closing (0:15)

**Slide**
- **Defense-in-depth is a continuous process, not a finished product.**
- Each layer is expected to fail against some class of attack → security is making sure the **next layer / next sensor is already watching the gap**

**Speaker script**
> 「一句話總結：縱深防禦是一個持續的過程，不是一個完成的產品。每一層都會被某種
> 攻擊繞過——真正重要的是，下一層是不是已經在盯著那個缺口。」

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
