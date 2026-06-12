# Blue Team Defense — 10-Minute Presentation Outline

**Source:** `docs/BLUE_TEAM_REPORT.tex` (Group 6, Blue Team)
**Duration:** 10:00 talk + 5:00 Q&A · **Format:** bullets on slides + spoken script + screenshots
**Emphasis:** defend **Project 1's attack** — organized **along the kill chain** (honeypot + eBPF are the deep-dives)
**Narrative arc (起承轉合):** Setup → Development → Turn → Resolution

> 投影片文字維持英文；下方的「Speaker script（講稿）」為中文口語稿。
> 「Screenshot / Visual」標明該擷取的畫面（程式碼行數或報告圖表）。

---

> ### 📌 改版說明（依老師 06/13 期末報告意見，2026-06-12）
> 老師意見三點：①**以防禦 Project 1（紅隊）的攻擊為主** ②**從 Kill Chain 探討防禦** ③攻擊流程可略提、防禦為主。
> 本版調整：把**敘事主軸從「防禦層」改成「攻擊 kill chain」**——
> - **S1** 用 Project 1 的六階段 kill chain 開場（略提攻擊，滿足③），點明「每一階段我們怎麼接招」。
> - **S2** 改成 **kill-chain ↔ 防禦控制對應**（報告 `tab:coverage`）＝直接回應②，當作整場的骨架（spine）。
> - **S3–S7** 每張深入投影片都掛上「擋的是哪個 kill-chain 階段＋對應 Project 1 哪一招」的標籤。
> - **S8** 缺口改寫成「kill chain 上沒守住的階段」（initial access / exfil / persistence 三個 Gap 列）。
> - 末尾新增 **Q&A 備答清單**（對應 5 分鐘 QA）。
> honeypot + eBPF 的程式碼深度與截圖全部保留（仍是技術強項）。

---

## Pacing table (total 10:00)

| # | Slide | Act | Kill-chain stage defended | Time | Cumulative |
|---|---|---|---|---|---|
| 0 | Title | — | — | 0:15 | 0:15 |
| 1 | The attack we must defend (Project 1 kill chain) | **Setup (起)** | (overview) | 1:00 | 1:15 |
| 2 | Defense mapped onto the kill chain | **Setup (起)** | (the spine) | 1:00 | 2:15 |
| 3 | Honeypot deception (code) | **Development (承)** | Recon | 1:00 | 3:15 |
| 4 | Network MDR auto-block + its bypass (code) | **Development (承)** | Recon→Access pivot | 0:45 | 4:00 |
| 5 | Why eBPF | **Development (承)** | (Execution/C2 setup) | 0:45 | 4:45 |
| 6 | eBPF: killing the fileless install + ICMP C2 (code) | **Development (承)** | Installation + C2 | 1:30 | 6:15 |
| 7 | eBPF: reverse-shell C2 + kernel kill (code) | **Development — climax (承)** | C2 (evasion) | 1:30 | 7:45 |
| 8 | Where the chain still gets through | **Turn (轉)** | Access / Exfil / Persistence (gaps) | 1:15 | 9:00 |
| 9 | Lessons & hardening | **Resolution (合)** | (close the gaps) | 0:45 | 9:45 |
| 10 | Closing | **Resolution (合)** | — | 0:15 | 10:00 |

> Core slides S3–S7 (~5.5 min) are all honeypot + eBPF — the requested technical focus, now each
> labelled with the kill-chain stage it defends so the through-line is explicit.

---

## S0 — Title (0:15)

**Slide**
- **Blue Team Defense — Defending the Kill Chain with Behavior-based Detection & Kernel Response**
- Group 6 · members · date

**Speaker script**
> 「我們攻擊組那份報告，已經把一整條 kill chain 從偵察打到資料外洩。今天我換到防守方，
> 不是逐項講我們有哪些工具，而是**沿著同一條攻擊鏈走一遍**——攻擊每前進一步，
> 看我們在那一步上接得住、還是接不住。」

---

## S1 — Setup (起): The attack we must defend — Project 1's kill chain (1:00)

**Slide**
- We defend **the exact attack from Project 1**, read as a kill chain (attacker already lands as **root**, payload is **fileless**):

| # | Kill-chain stage | Project 1 action (ATT&CK) |
|---|---|---|
| 1 | **Recon** | `nmap` port/service scan (T1595) |
| 2 | **Delivery / Exploit** | SSTI into the diag API → RCE (T1190) |
| 3 | **Install** | `memfd_create` fileless loader → `execve /proc/fd` (T1620) |
| 4 | **C2** | covert ICMP channel / TCP reverse shell (T1095 / T1059.006) |
| 5 | **Actions** | DNS/ICMP exfil (T1048.003) + `cron` persistence (T1053.003) |

- Two consequences shape the whole defense: **the front door (SSTI) is already lost**, and **disk scanning is useless (fileless)** → defense must be **watch behavior, respond in real time**.

**Speaker script**
> 「先把我們要守的東西講清楚——就是攻擊組 Project 1 那條鏈，原封不動。它分五步：偵察、用 SSTI 打進來、
> 在記憶體裡 fileless 載入、開一條 C2 控制通道、最後外洩資料加裝常駐。
> 兩個前提決定了我們整套打法：第一，SSTI 這道門我們**已經守不住了**，root 也被拿走了；
> 第二，payload 是 fileless 的，磁碟上沒東西可掃。所以我們不押在『把門擋住』，
> 而是沿著這條鏈，盯每一步的**行為**、然後即時反應。」

**Screenshot / Visual**
- Red-team report §4 kill-chain table, or `RED_TEAM_PLAYBOOK.md` 的「攻擊流程 (Kill Chain)」清單。

---

## S2 — Setup (起): Defense mapped onto the kill chain (1:00) — **the spine**

**Slide**
- One control per stage; some **enforce** (stop it), some only **alert**, some are **honest gaps**:

| Kill-chain stage | Defensive control | Layer | Action |
|---|---|---|---|
| Recon | Honeypot (`:2222`) + `iptables` MDR | Network | Alert → **block IP** |
| Exploit (SSTI) | — *(no WAF)* | — | **Gap** |
| Install (memfd) | `sys_enter_memfd_create` (taint) | Kernel/eBPF | Alert |
| Install (`/proc/fd` exec) | `sys_enter_execve` argv check | Kernel/eBPF | **Kill** |
| C2 (raw ICMP) | `sys_enter_socket` + correlation | Kernel/eBPF | **Kill if correlated** |
| C2 (reverse shell) | `sys_enter_dup2/dup3` bitmask | Kernel/eBPF | **Kill** |
| Exfil (DNS) / Persistence (cron) | — | — | **Gap** |

- **Two layers, by design:** Layer 1 (network) is cheap + earliest signal but bypassable; Layer 2 (kernel/eBPF) is the real enforcer — it acts on **behavior**, so it does not care about IP or file hash.

**Speaker script**
> 「這張是整場的骨架。我把剛剛那條鏈攤平，每一個階段配一個防禦控制，
> 而且**誠實標出**哪些是真的能攔（綠的 enforce）、哪些只是記一筆（alert）、哪些根本沒守住（紅的 gap）。
> 你會看到我們的防守集中在兩層：第一層在網路，最便宜、最早給訊號，可是最好繞；
> 第二層在 kernel 用 eBPF，是真正動手攔的地方，它盯的是行為，所以**換 IP、改檔名都沒用**。
> 接下來幾頁，就是照這張表，一階段一階段帶你看。」

**Screenshot / Visual**
- Report **Table 1 「Detection-and-response coverage」(`tab:coverage`)** — 這張表就是這頁的母本。
- 搭配 Report **Figure「Defense-in-depth」(`fig:did`)** 當左右並陳。

---

## S3 — Development (承): Honeypot — defending **Recon** (1:00)

> **Kill-chain stage:** Recon (T1595) · **counters Project 1 Phase 1 `nmap`**

**Slide**
- Fake SSH on `:2222`: banner is **byte-for-byte** a real OpenSSH version string → indistinguishable to `nmap -sV`
- **Near-zero false positive:** nothing legitimate connects to `:2222` → any hit is the attacker enumerating us
- Every hit appended to `trap.log` (IP / port / first 100 bytes) — the contract handed to the MDR

**Speaker script**
> 「第一步，偵察。攻擊組一定會掃 port，我們就在 `:2222` 放一個假 SSH 當誘餌。
> 回給它的 banner 跟真的 OpenSSH 版本字串一模一樣，掃描器分不出來。
> 蜜罐最大的好處是**訊號乾淨**——正常服務根本不會有人連 `:2222`，所以只要有人連上來，
> 幾乎可以確定就是在踩點。我們把它的 IP 寫進 `trap.log`，這就是交給下一個元件的情報。」

**Screenshot / Visual** — code: `target/honeypot.py`
- **L30–36** — `SSH_BANNER` / `FAKE_RESPONSE`
- **L50–78** — send banner + write the `trap.log` line

---

## S4 — Development (承): Network MDR auto-block — and its bypass (0:45)

> **Kill-chain stage:** Recon → Initial-Access pivot · **counters Project 1, but Phase 5 IP-alias breaks it**

**Slide**
- Tails `trap.log`; on a new IP runs `iptables -I INPUT 1 -s <ip> -j DROP` (insert at pos 1 = cuts the IP off **all** ports in < 1 s)
- **First hand-off in the chain:** it blocks the **source IP** — and in Project 1 the source IP is attacker-controlled
- Project 1 Phase 5 defeats it with **one alias IP** → fresh identity → reaches `:9999` again → *the chain moves to Layer 2*

**Speaker script**
> 「蜜罐一抓到新 IP，我們不到一秒就插一條最高優先權、擋掉所有 port 的 DROP 規則，那個 IP 整台被切掉。
> 但這也正是它的罩門：它擋的是 source IP，而在 Project 1 裡，source IP 是攻擊者自己控制的——
> 他加一個 alias IP，等於換了一張新身分證，又連回 `:9999`。
> 所以這一層**註定會被繞過**，這不是 bug，是設計上預期的：它的任務是給最早的訊號，
> 然後把球**交給第二層**。」*（這裡埋伏筆，接到 S8 的「轉折」）*

**Screenshot / Visual** — code: `blue_team/blue_mdr_network.py`
- **L47–52** — `block_ip()` (the `iptables` command)
- **L87–119** — watcher: `seek` to end of file, extract new IPs, call block

---

## S5 — Development (承): Why eBPF — the enforcer for stages 3–4 (0:45)

**Slide**
- **Source-IP-agnostic** — acts on behavior; Layer-1's IP-alias bypass is irrelevant here
- **Fileless-visible** — sees `memfd_create` / `execve` arguments directly (disk scan saw nothing)
- **Pre-syscall enforcement** — hooks fire at `sys_enter_*`, *before* the dangerous action completes
- **Low overhead** — verifier-checked, JIT-compiled to native code, O(1) hash-map lookups

**Speaker script**
> 「為什麼第二層要用 eBPF？因為攻擊鏈接下來的步驟，剛好打中網路層的三個盲點：
> 它不看 IP（所以剛剛換 IP 的招對它無效）、它能直接看到 fileless 的 `memfd`、`execve` 參數，
> 而且它掛在 syscall 的**進入點**，可以在那個危險動作真的發生**之前**就先攔下來。
> 它是一支被 kernel verifier 檢查過、JIT 成原生碼的程式，所以放在 kernel 裡跑也夠輕。」

**Screenshot / Visual**
- Report **Figure「eBPF pipeline」(`fig:pipeline`)** (C → BCC → bytecode → verifier → JIT → tracepoint → perf buffer).

---

## S6 — Development (承): Killing the fileless install + ICMP C2 (1:30)

> **Kill-chain stage:** Install (T1620) + C2 (T1095) · **counters Project 1 Phase 2 memfd→ICMP**

**Slide**
- Hook 1 `memfd_create` → **alert + taint** the process (don't kill — memfd has benign uses)
- Hook 0 `fork` → **propagate the taint** to children (one fork shouldn't shake off tracking)
- Hook 2 `execve` → argv points at `/proc/<pid>/fd/<N>` = fileless loader → **KILL** (this is the install step in the chain)
- Hook 3 raw ICMP socket → alone only alerts; **correlated with memfd taint → KILL** (this is the C2 step)
- Design principle: **enforce only on the highest-confidence signal**, alert on the rest
- **Cold-start `/proc` scanner**: if the MDR starts *after* the agent is already running, it still finds and kills the in-memory `python3 /proc/<pid>/fd/<N>` (compensating control)

**Speaker script**
> 「現在進到第三、第四步：fileless 載入跟 C2。攻擊鏈是 `memfd` 先在記憶體開一個檔，
> 再透過 `/proc/fd` 執行它。我們不會在 `memfd` 那一步就殺，因為它本身有正常用途——
> 我們只是把這個行程**標記**起來，連 fork 出來的小孩也一起標。
> 真正動手是在 `execve` 看到 argv 指到 `/proc/fd` 這個 pattern 的時候，那就確定是 fileless loader，**直接 kill**。
> C2 那條 ICMP，單獨看只記一筆，但只要它跟前面 memfd 的標記**對得上**，也殺。
> 還有一個情境：如果我們是在 agent 已經在跑之後才開防禦，有一支 `/proc` 掃描器會把它揪出來補殺。」

**Screenshot / Visual** — code: `blue_team/blue_ebpf_mdr_v2.py`
- **L106–116** — memfd hook (`__KILL_MEMFD__` empty = alert-only / taint)
- **L149–178** — `execve` argv `/proc/fd` check → `__KILL_EXEC__`
- **L196–211** — raw ICMP + correlation → `__KILL_ICMP_CORR__`
- *(optional)* cold-start `/proc` scanner — report §"Cold-start `/proc` scanner"

---

## S7 — Development climax (承): Reverse-shell C2 + kernel kill (1:30)

> **Kill-chain stage:** C2 via evasion (T1059.006/T1571) · **counters Project 1 Phase 5 — the move that bypassed eBPF v1**

**Slide**
- In Project 1, the attacker **adapts**: a pure TCP reverse shell uses only ordinary syscalls (`socket → connect → dup2 → pty`) → the four staging hooks of S6 stay **silent by design**
- Same tool still catches it, on a **different, higher-confidence** signal:
  - Hooks 5/6 `dup2`/`dup3`: per-PID bitmask — stdin/stdout/stderr each set one bit
  - All three redirected to the **same socket** → mask `0x07` → **confirmed reverse shell → SIGKILL**
- **Port-agnostic** (catches it on 80/443 too); `dup3` hooked as well (`inheritable=False` path)
- Kill = `bpf_send_signal(9)`, **in-kernel, before the syscall completes** → no userspace race

**Speaker script**
> 「這一頁是高潮，也是 Project 1 最聰明的一手。攻擊者發現 memfd 那條被擋了，
> 就改用純 TCP 的 reverse shell——不用 memfd、不用 raw ICMP，前面四個 hook 全部**故意打不到**。
> 但我們不用改版就接得住，因為我們換看一個**更高可信度**的行為：
> reverse shell 一定會把 stdin、stdout、stderr 三個都接到同一個 socket。
> 我們用一個 bitmask 去追，三個 fd 各佔一個 bit，湊齊變 `0x07` 就確定是 reverse shell，
> 直接 `bpf_send_signal` 殺掉——而且是在 syscall 還沒做完之前、在 kernel 裡動手，不管它走 80 還是 443 都擋得下來。」

**Screenshot / Visual**
- **Figure:** report **「Reverse-shell bitmask state machine」(`fig:dup2`)** (`000 → 001 → 011 → 111 → SIGKILL`) — best climax visual
- **Code:** `blue_team/blue_ebpf_mdr_v2.py`
  - **L279–300** — `dup2` bitmask → `0x07` kill
  - **L454–457** — load-time injection: `__KILL_*__` replaced with `e.killed = 1; bpf_send_signal(9);` (one C source, two behaviors: monitor vs `--kill`)

---

## S8 — Turn (轉): Where the chain still gets through (1:15)

> **Kill-chain stages with no control:** Initial-Access (T1190) · Exfil (T1048.003) · Persistence (T1053.003)

**Slide**
- Reading the **same kill chain**, three stages are still open — honestly:
  - **Exploit (T1190):** SSTI itself is **never detected** — we only catch what it *spawns*. No WAF = the entry stays open.
  - **Exfil (T1048.003):** DNS exfil uses only `socket(SOCK_DGRAM)+sendto` to `:53` → **all legitimate syscalls → no hook fires**. eBPF is blind to malice done with "good" syscalls.
  - **Persistence (T1053.003):** a planted `crontab` re-downloads the agent → killing a process doesn't remove its launcher.
- Plus two structural caveats: **IP block is reactive/bypassable** (NAT/proxy generalize the alias trick); **the detector is itself a risk** — a misclassified `bpf_send_signal(9)` is a self-inflicted DoS.
- **Root cause remains:** SSTI + running as root were never fixed.

**Speaker script**
> 「接下來講比較誠實的部分。把同一條 kill chain 再看一次，有三個階段我們其實沒守住：
> 第一，SSTI 那個入口我們**從頭到尾沒偵測到**，我們只抓它生出來的東西，沒有 WAF 門就一直開著；
> 第二，資料外洩走 DNS，它用的全是正常 syscall——`socket`、`sendto` 打到 53 port，
> 我們一個 hook 都不會響，eBPF 對『用好的 syscall 做壞事』是瞎的；
> 第三，cron 這種常駐，你 kill 幾次它都會被重新拉起來，因為殺行程不等於清掉它的啟動器。
> 另外還有兩個風險：換 IP 就破第一層（NAT、proxy 都是同一招的放大版）；
> 還有我們自己的偵測器只要誤判一次，那一發 `bpf_send_signal` 就等於自己把服務弄掛、變成 DoS。
> 而且最根本的——SSTI 跟用 root 跑，我們從頭到尾都沒修。」

**Screenshot / Visual**
- Report **Table 1 (`tab:coverage`)** 的三個 **Gap** 列（T1190 / T1048.003 / T1053.003）反白標紅。
- 或 Report **Figure「attack–defense rounds」(`fig:rounds`)** 最右邊的紅色 `full-stack gap (DNS+cron)` 區塊。

---

## S9 — Resolution (合): Lessons & hardening — closing each gap (0:45)

**Slide**
- **Exfil gap →** enumerating "bad" syscalls can't see malice in "good" ones → add a **different sensor**: egress/DNS analytics, not another syscall hook
- **Persistence gap →** needs **eradication** (watch cron/systemd/rc files), not just process kills
- **False-positive/DoS risk →** move from single-signal kills to **scoring** (correlate `connect` + `dup2` + new-socket) → auto-kill only on high scores, else **quarantine**
- **Root cause →** patch the SSTI, drop root, add a WAF → so Layer 2 becomes a **backstop, not the only wall**

**Speaker script**
> 「每個缺口其實都有對應的解法，而且都對著剛剛 kill chain 那幾個破口：
> 外洩那一段要靠 DNS 流量分析這類**另一種感測器**，不是再加 syscall hook；
> 常駐要的是**徹底清掉**啟動器，不是只殺行程；
> 至於誤判的風險，把『單一訊號就殺』改成『**看分數**』，分數夠高才殺、不然先隔離，可以少掉很多自殘式的 DoS。
> 但最重要的還是把入口補起來——修掉 SSTI、不要用 root 跑、加一道 WAF，
> 讓 kernel 這層回到它該有的位置：是**最後一道後援**，而不是唯一一道牆。」

---

## S10 — Resolution (合): Closing (0:15)

**Slide**
- **Defense-in-depth is a continuous process, not a finished product.**
- Every layer is expected to fail against some stage of the kill chain → security is making sure **the next layer / next sensor is already watching that stage**.

**Speaker script**
> 「一句話收尾：縱深防禦是一個持續的過程，不是做完就結束的產品。
> kill chain 上每一層一定都會被某一階段繞過，真正重要的是——下一層、下一個感測器，
> 有沒有已經在盯著那個破口。」

**Screenshot / Visual (optional)**
- Report **「attack–defense rounds」(`fig:rounds`)** 整張當收尾全景（綠 / 琥珀 / 紅）。

---

## Q&A 備答（對應 5 分鐘 QA）

> 老師可能追問的點，先備好一句話答案（都對得回投影片或報告）。

| 可能問題 | 一句話回答 | 對應 |
|---|---|---|
| 「為什麼 SSTI 本身不擋？」 | 範圍刻意放在「進來之後」的偵測與反應；入口屬 WAF/應用層修補，我們在 S9 列為首要 hardening、S8 標為 Gap。 | S8/S9 |
| 「eBPF 殺錯怎麼辦？」 | 只在最高可信度訊號 enforce（execve `/proc/fd`、dup2 `0x07`），其餘只 alert；S9 提出改 scoring + 隔離降誤判。 | S6/S7/S9 |
| 「IP 封鎖能擋多久？」 | 設計上預期被 alias 繞過，任務是給最早訊號並把球交給 L2；真正攔截在行為層。 | S4/S2 |
| 「reverse shell 換 port 還抓得到嗎？」 | 抓得到——dup2 bitmask 是 port-agnostic，連 80/443 都吃，因為盯的是 fd 重導不是 port。 | S7 |
| 「DNS 外洩為什麼漏？」 | 它只用合法 syscall（`socket SOCK_DGRAM`+`sendto`），syscall 列舉式偵測本質看不到 → 要 egress/DNS 分析這種不同感測器。 | S8/S9 |
| 「cold start（防禦比攻擊晚開）呢？」 | `/proc` 掃描器補抓已在跑的 `python3 /proc/<pid>/fd/<N>` agent，對應報告 R3 回合。 | S6 |
| 「這套對真實環境的 overhead？」 | hooks 掛 `sys_enter_*`、O(1) hash-map、JIT 原生碼；kernel 內判斷不進 userspace，無 race。 | S5/S7 |

---

## Asset checklist

**Code screenshots**
| Slide | Kill-chain stage | File | Lines | What it shows |
|---|---|---|---|---|
| S3 | Recon | `target/honeypot.py` | 30–36 | fake SSH banner / fake rejection |
| S3 | Recon | `target/honeypot.py` | 50–78 | send banner + write `trap.log` |
| S4 | Recon→Access | `blue_team/blue_mdr_network.py` | 47–52 | `iptables -I INPUT 1 ... DROP` |
| S4 | Recon→Access | `blue_team/blue_mdr_network.py` | 87–119 | tail `trap.log`, block new IPs |
| S6 | Install | `blue_team/blue_ebpf_mdr_v2.py` | 106–116 | memfd hook (alert-only / taint) |
| S6 | Install | `blue_team/blue_ebpf_mdr_v2.py` | 149–178 | `execve` argv `/proc/fd` → kill |
| S6 | C2 (ICMP) | `blue_team/blue_ebpf_mdr_v2.py` | 196–211 | raw ICMP + correlation → kill |
| S7 | C2 (revshell) | `blue_team/blue_ebpf_mdr_v2.py` | 279–300 | `dup2` bitmask → `0x07` kill |
| S7 | C2 (revshell) | `blue_team/blue_ebpf_mdr_v2.py` | 454–457 | load-time `bpf_send_signal(9)` injection |

**Report figures / tables** (from `BLUE_TEAM_REPORT.pdf`)
| Slide | Asset | Section / label |
|---|---|---|
| S1 | Red-team kill-chain table (attack stages) | red-team report §4 |
| S2 / S8 | Table 1 「Detection coverage」(the kill-chain ↔ control map) | `tab:coverage` |
| S2 | Figure「Defense-in-depth」 | `fig:did` |
| S5 | Figure「eBPF pipeline」 | `fig:pipeline` |
| S7 | Figure「Reverse-shell bitmask state machine」 | `fig:dup2` |
| S8 / S10 | Figure「attack–defense rounds」 | `fig:rounds` |

**Optional live-evidence screenshots** (red-team report or your own re-run)
- Honeypot trap fired · IP-alias bypass · C2 beacon established · exfil loot reassembled
- Or your SOC dashboard / `trap.log` / a kill event from `soc_events.jsonl`
