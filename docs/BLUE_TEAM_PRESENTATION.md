# Blue Team Defense — 10-Minute Presentation Outline

**Source:** `docs/BLUE_TEAM_REPORT.tex` (Group 6, Blue Team) · **Attack defended:** `Network_Security_Hands_on_2_1.pdf` (Project 1 — Group 6 Attack)
**Duration:** 10:00 talk + 5:00 Q&A · **Format:** bullets on slides + spoken script + screenshots
**Emphasis:** defend **Project 1's actual attack** — organized **along the Cyber Kill Chain** (honeypot + eBPF are the deep-dives)
**Narrative arc (起承轉合):** Setup → Development → Turn → Resolution

> 投影片文字維持英文；下方的「Speaker script（講稿）」為中文口語稿。
> 「Screenshot / Visual」標明該擷取的畫面（程式碼行數或報告圖表）。

---

> ### 📌 改版說明（依老師 06/13 意見 + 對齊 Project 1 正式檔，2026-06-12）
> 老師三點：①**以防禦 Project 1（紅隊）的攻擊為主** ②**從 Kill Chain 探討防禦** ③攻擊流程可略提、防禦為主。
> **⚠ 對齊 Project 1 正式報告 `Network_Security_Hands_on_2_1.pdf`**（與 demo 有出入，照正式檔）：
> - Project 1 驗證路徑 = `Recon → HoneypotTrigger → IPBypass → SSTI → FilelessC2 → CommandExecution → Exfiltration`
>   （Lockheed-Martin 7 階 Cyber Kill Chain；用這條當骨架）。
> - **Project 1 的 C2 只有 fileless ICMP**——**沒有 TCP reverse shell**（ATT&CK 清單無 T1571）。原 S7 reverse-shell
>   改標為「**anticipated evasion / blue round R5，超出 Project 1 範圍**」，誠實保留為縱深亮點、不謊稱 Project 1 做過。
> - **Project 1 沒有 cron 持久化**（清單無 T1053.003）；exfil = HTTP 拉 `exfil_agent.py` → `nohup &` → DNS/ICMP 外洩
>   `passwd`/`shadow`/`.bash_history`（loot 裡的 crontab 是被偷的檔，非攻擊者種的常駐）。S8 缺口移除 cron 宣稱。
> - **關鍵框架**：Project 1 那次**只有網路層在線、eBPF out of scope**（其報告 §1.3/§2.3/§6.1 明寫）→ 被 IP-alias 繞過後
>   SSTI 之後全暢通、exfil 成功。**藍隊論點＝kernel(eBPF) 層在 FilelessC2 重新接管、在 CommandExecution 前殺掉 agent**。
> honeypot + eBPF 程式碼深度與截圖全保留。⚠ 報告 .tex 的 R5(reverse shell)/R6(cron) 也與 Project 1 不符 → 見末尾備註。

---

## Pacing table (total 10:00)

| # | Slide | Act | Kill-chain stage defended | Time | Cumulative |
|---|---|---|---|---|---|
| 0 | Title | — | — | 0:15 | 0:15 |
| 1 | The attack we must defend (Project 1's kill chain) | **Setup (起)** | (overview) | 1:00 | 1:15 |
| 2 | Defense mapped onto the kill chain | **Setup (起)** | (the spine) | 1:00 | 2:15 |
| 3 | Honeypot deception (code) | **Development (承)** | Recon + Honeypot-trigger | 1:00 | 3:15 |
| 4 | Network MDR auto-block + the IP-alias bypass (code) | **Development (承)** | Honeypot-trigger → IP-bypass | 0:45 | 4:00 |
| 5 | Why eBPF — re-taking control after the bypass | **Development (承)** | (SSTI → Install setup) | 0:45 | 4:45 |
| 6 | eBPF: killing the fileless ICMP C2 (code) | **Development — climax (承)** | Install + C2 (Project 1's actual C2) | 1:45 | 6:30 |
| 7 | eBPF: the anticipated reverse-shell evasion (code) | **Development (承)** | C2 evasion *(beyond Project 1)* | 1:15 | 7:45 |
| 8 | Where the chain still gets through | **Turn (轉)** | Exploit (SSTI) + Exfiltration (gaps) | 1:15 | 9:00 |
| 9 | Lessons & hardening | **Resolution (合)** | (close the gaps) | 0:45 | 9:45 |
| 10 | Closing | **Resolution (合)** | — | 0:15 | 10:00 |

> Core slides S3–S7 (~5.5 min) are all honeypot + eBPF. S6 (the fileless ICMP C2) is the climax because it is
> **the exact C2 Project 1 ran** and the first stage where the kernel layer re-takes control after the network bypass.

---

## S0 — Title (0:15)

**Slide**
- **Blue Team Defense — Re-taking the Kill Chain with Behavior-based Detection & Kernel Response**
- Group 6 · members · date

**Speaker script**
> 「我們攻擊組那份 Project 1，已經把一整條 kill chain 從偵察打到資料外洩，而且**打穿了**。
> 今天我換到防守方，沿著**同一條攻擊鏈**走一遍——重點是說清楚：那次為什麼會被打穿，
> 以及如果把我們的 kernel 層補上去，攻擊在哪一步會被擋下來。」

---

## S1 — Setup (起): The attack we must defend — Project 1's kill chain (1:00)

**Slide**
- We defend **the exact attack from Project 1** (attacker lands as **root**, C2 is **fileless**). Validated path:

  `Recon → Honeypot-trigger → IP-bypass → SSTI → Fileless ICMP C2 → Command-exec → Exfiltration`

| Kill-chain phase | Project 1 action (ATT&CK) |
|---|---|
| **Recon** | `nmap` finds `:2222` (honeypot) vs `:9999` (real portal) — T1595 |
| **Honeypot-trigger → IP-bypass** | hits `:2222` from `.14`, then adds alias `.15` to keep going |
| **Exploit (Delivery)** | SSTI into the `:9999` diag portal → RCE — T1190 |
| **Install** | `memfd_create` loader → `execve /proc/<pid>/fd/<N>` — T1620 / T1059.006 |
| **C2** | **fileless ICMP** beacon (AES-CTR in echo payload) — T1095 |
| **Actions** | interactive cmds, then DNS/ICMP exfil of `passwd`/`shadow` — T1048.003 |

- **The Project 1 outcome:** that run had **only the network layer live** (their report: eBPF out of scope) → once the IP block was bypassed, **everything from SSTI onward completed unopposed**.

**Speaker script**
> 「先把要守的東西講清楚——就是 Project 1 那條鏈，原封不動。偵察找到真目標 `:9999`，
> 故意踩一下蜜罐、再換 IP 繞過封鎖，然後用 SSTI 打進來、在記憶體裡 fileless 載入、
> 開一條**走 ICMP** 的 C2、下指令、最後把 `passwd`、`shadow` 這些檔案外洩出去。
> 這裡有個關鍵：Project 1 那次**只有網路層在跑**，他們報告自己寫 eBPF 不在那次範圍裡。
> 所以網路層一被繞過，後面 SSTI 到外洩**整段沒人擋**就完成了。今天的重點，就是把缺的那層補回來。」

**Screenshot / Visual**
- Project 1 PDF §2.1「Cyber Kill Chain」的 path 字串 + §4 Attack-Chain table（Recon→…→Exfiltration）。

---

## S2 — Setup (起): Defense mapped onto the kill chain (1:00) — **the spine**

**Slide**
- One control per phase; some **enforce** (stop it), some only **alert**, some are **honest gaps**:

| Kill-chain phase | Defensive control | Layer | Action |
|---|---|---|---|
| Recon | Honeypot (`:2222`) | Network | **Alert** (clean signal) |
| Honeypot-trigger | `iptables` MDR | Network | **Enforce** (block IP) |
| IP-bypass | *(IP block is reactive)* | — | **Bypassed** → hand to L2 |
| Exploit (SSTI) | *(no WAF)* | — | **Gap** |
| Install (`/proc/fd` exec) | `sys_enter_execve` argv check | Kernel/eBPF | **Kill** |
| C2 (raw ICMP) | `memfd` taint + raw-ICMP correlation | Kernel/eBPF | **Kill** |
| Command-exec | *(agent already killed upstream)* | Kernel/eBPF | **Prevented** |
| Exfiltration (DNS) | *(legitimate syscalls only)* | — | **Gap** |

- **Two layers, by design.** Network layer = cheap, earliest signal, **bypassable** (Project 1 bypassed it). Kernel/eBPF layer = the real enforcer — acts on **behavior**, so the IP-alias trick is irrelevant to it. **It re-takes control at Install/C2** — the first kernel-touching step after the bypass.

**Speaker script**
> 「這張是整場的骨架。我把那條鏈攤平，每一階段配一個防禦控制，而且**誠實標出**
> 哪些真的能攔、哪些只是記一筆、哪些根本沒守住。你會看到 Project 1 被打穿的點就在第三格——
> 網路層的 IP 封鎖是反應式的，被換 IP 繞過。但**第二層 eBPF 不看 IP、看行為**，
> 所以它在 Install 跟 C2 這兩步重新接管——這是繞過之後第一個會碰到 kernel 的動作。
> 接下來幾頁就照這張表，一階段一階段帶你看。」

**Screenshot / Visual**
- Report **Table 1「Detection-and-response coverage」(`tab:coverage`)** — 這張表就是這頁的母本。
- 搭配 Report **Figure「Defense-in-depth」(`fig:did`)** 左右並陳。

---

## S3 — Development (承): Honeypot — defending **Recon** (1:00)

> **Kill-chain phase:** Recon (T1595) + Honeypot-trigger · **counters Project 1's `nmap` + `:2222` hit**

**Slide**
- Fake SSH on `:2222`: banner is **byte-for-byte** a real OpenSSH version string → indistinguishable to `nmap -sV`
- **Near-zero false positive:** nothing legitimate connects to `:2222` → any hit is the attacker enumerating us (Project 1 hit it from `.14`)
- Every hit appended to `trap.log` (IP / port / first 100 bytes) — the contract handed to the MDR

**Speaker script**
> 「第一步，偵察。Project 1 一開始就掃 port，掃到 `:2222` 跟 `:9999`。我們在 `:2222` 放假 SSH 當誘餌，
> 回給它的 banner 跟真的 OpenSSH 版本字串一模一樣，掃描器分不出來。
> 蜜罐最大的好處是**訊號乾淨**——正常服務不會有人連 `:2222`，所以一被連上，幾乎確定是在踩點。
> Project 1 那次就從 `.14` 連上來，我們把它的 IP 寫進 `trap.log`，這是交給下一個元件的情報。」

**Screenshot / Visual** — code: `target/honeypot.py`
- **L30–36** — `SSH_BANNER` / `FAKE_RESPONSE`
- **L50–78** — send banner + write the `trap.log` line
- *(對照)* Project 1 PDF Fig 2a「Trigger the fake SSH honeypot」

---

## S4 — Development (承): Network MDR auto-block — and Project 1's IP-alias bypass (0:45)

> **Kill-chain phase:** Honeypot-trigger → IP-bypass · **this is exactly where Project 1 got through**

**Slide**
- Tails `trap.log`; on a new IP runs `iptables -I INPUT 1 -s <ip> -j DROP` (insert at pos 1 = cuts the IP off **all** ports in < 1 s)
- It blocks the **source IP** — and in Project 1 the source IP is attacker-controlled
- **Project 1's bypass:** add alias `192.168.1.15` → fresh identity → reaches `:9999` again → *the network layer is beaten; the chain must be caught later, in the kernel*

**Speaker script**
> 「蜜罐一抓到新 IP，我們不到一秒就插一條最高優先權、擋掉所有 port 的 DROP，那個 IP 整台被切掉。
> 但這也是它的罩門：它擋的是 source IP，而 source IP 是攻擊者自己控制的。
> Project 1 就是在這裡破的——他加一個 alias IP `.15`，等於換一張新身分證，又連回 `:9999`。
> 所以這一層**註定會被繞過**，這不是 bug，是設計上預期的：它的任務是給最早的訊號、買時間，
> 然後把球**交給第二層**。Project 1 的故事到這裡，網路層就出局了。」*（埋伏筆，接 S6 的「接管」）*

**Screenshot / Visual** — code: `blue_team/blue_mdr_network.py`
- **L47–52** — `block_ip()` (the `iptables` command)
- **L87–119** — watcher: `seek` to end of file, extract new IPs, call block
- *(對照)* Project 1 PDF Fig 2b「Add alias IP 192.168.1.15」

---

## S5 — Development (承): Why eBPF — re-taking control after the bypass (0:45)

**Slide**
- After the IP bypass, the **next** attacker actions (SSTI → memfd → execve → ICMP) all touch the **kernel** — that's where eBPF lives
- **Source-IP-agnostic** — acts on behavior; the IP-alias bypass is irrelevant here
- **Fileless-visible** — sees `memfd_create` / `execve` arguments directly (disk scan saw nothing)
- **Pre-syscall enforcement** — hooks fire at `sys_enter_*`, *before* the dangerous action completes
- **Low overhead** — verifier-checked, JIT-compiled to native code, O(1) hash-map lookups

**Speaker script**
> 「為什麼第二層用 eBPF？因為 Project 1 繞過網路層之後，接下來每一步——SSTI 生出來的 loader、
> `memfd`、`execve`、ICMP——**全都會經過 kernel**，而 eBPF 就掛在那裡。
> 它不看 IP，所以剛剛換 IP 那招對它無效；它能直接看到 fileless 的 syscall 參數；
> 而且掛在 syscall 的**進入點**，可以在危險動作真的發生**之前**就攔下來。」

**Screenshot / Visual**
- Report **Figure「eBPF pipeline」(`fig:pipeline`)** (C → BCC → bytecode → verifier → JIT → tracepoint → perf buffer).

---

## S6 — Development climax (承): Killing the fileless ICMP C2 (1:45)

> **Kill-chain phase:** Install (T1620) + C2 (T1095) · **this is Project 1's *actual* C2 — and where we re-take control**

**Slide**
- Project 1's chain: `SSTI → memfd_create → write agent → fork → execve /proc/<pid>/fd/<N> → ICMP beacon`
- Hook 1 `memfd_create` → **alert + taint** the process (don't kill — memfd has benign uses)
- Hook 0 `fork` → **propagate the taint** to children (one fork shouldn't shake off tracking)
- Hook 2 `execve` → argv points at `/proc/<pid>/fd/<N>` = the fileless loader → **KILL** ← *agent never runs → no beacon → no command-exec → no exfil*
- Hook 3 raw ICMP socket → alone only alerts; **correlated with the memfd taint → KILL** (this is Project 1's exact ICMP C2)
- **Cold-start `/proc` scanner**: if the MDR starts *after* the agent is already running, it still finds and kills the in-memory `python3 /proc/<pid>/fd/<N>`
- **Design principle:** enforce only on the **highest-confidence** signal, alert on the rest

**Speaker script**
> 「這一頁是高潮，因為它擋的就是 Project 1 真正用的那條 C2。攻擊鏈是：SSTI 打進來，
> `memfd` 在記憶體開一個檔，寫進 agent，fork 之後用 `/proc/fd` 執行它，再透過 ICMP 回連。
> 我們不會在 `memfd` 那步就殺，因為它有正常用途——我們先把這個行程**標記**起來，連 fork 的小孩一起標。
> 真正動手是在 `execve` 看到 argv 指到 `/proc/fd` 的時候，**直接 kill**——agent 根本沒機會跑起來，
> 沒 beacon、沒下指令、後面也沒得外洩。那條 ICMP C2，單獨看只記一筆，但跟前面 memfd 標記**對得上**就殺。
> 還有一個情境：如果我們比 agent 晚開，有一支 `/proc` 掃描器會把已經在跑的揪出來補殺。
> 一句話：網路層在第四步出局，kernel 層在這一步**把控制權搶回來**。」

**Screenshot / Visual** — code: `blue_team/blue_ebpf_mdr_v2.py`
- **L106–116** — memfd hook (alert-only / taint)
- **L149–178** — `execve` argv `/proc/fd` check → kill
- **L196–211** — raw ICMP + correlation → kill
- *(對照)* Project 1 PDF Fig 5a「Beacon received」/ Fig 5c「cat /etc/hostname, ls」= 我們要在 beacon 出現前就殺掉的東西

---

## S7 — Development (承): The anticipated reverse-shell evasion (1:15)

> **Kill-chain phase:** C2 evasion · ⚠ **beyond Project 1 (it used ICMP); validated in blue round R5 as the attacker's natural next move**

**Slide**
- **Honest scope note:** Project 1's C2 was ICMP (S6). A motivated attacker, once the memfd/ICMP hooks are known, switches to a **pure TCP reverse shell** — `socket → connect → dup2 → pty` — which keeps **all four S6 hooks silent**. We validated this case ourselves (round R5).
- Same tool still catches it on a **different, higher-confidence** signal:
  - Hooks 5/6 `dup2`/`dup3`: per-PID bitmask — stdin/stdout/stderr each set one bit
  - All three redirected to the **same socket** → mask `0x07` → **confirmed reverse shell → SIGKILL**
- **Port-agnostic** (catches it on 80/443 too); `dup3` hooked as well
- Kill = `bpf_send_signal(9)`, **in-kernel, before the syscall completes**

**Speaker script**
> 「這一頁我先講清楚範圍：**Project 1 用的是 ICMP，沒有用 reverse shell**。但防守要想下一步——
> 攻擊者一旦知道我們在盯 memfd 跟 ICMP，最自然的閃法就是改用純 TCP 的 reverse shell，
> 完全不碰前面那四個 hook。這個情境我們自己驗過（R5 回合）。
> 我們換看一個更高可信度的行為：reverse shell 一定把 stdin、stdout、stderr 三個都接到同一個 socket。
> 用 bitmask 去追，湊齊 `0x07` 就確定，直接在 kernel 裡 `bpf_send_signal` 殺掉，連 80、443 都擋得下來。
> 這頁是『縱深』——就算攻擊者進化，我們的偵測也已經在等他了。」

**Screenshot / Visual**
- **Figure:** report **「Reverse-shell bitmask state machine」(`fig:dup2`)** (`000 → 001 → 011 → 111 → SIGKILL`)
- **Code:** `blue_team/blue_ebpf_mdr_v2.py`
  - **L279–300** — `dup2` bitmask → `0x07` kill
  - **L454–457** — load-time injection: `__KILL_*__` → `e.killed = 1; bpf_send_signal(9);` (one C source, monitor vs `--kill`)

---

## S8 — Turn (轉): Where the chain still gets through (1:15)

> **Kill-chain phases with no control (in Project 1):** Exploit (SSTI, T1190) · Exfiltration (DNS, T1048.003)

**Slide**
- Reading Project 1's **same chain**, two stages are still open — honestly:
  - **Exploit / SSTI (T1190):** the SSTI itself is **never detected** — we only catch what it *spawns* (the memfd/execve agent). No WAF = the entry stays open.
  - **Exfiltration / DNS (T1048.003):** Project 1's exfil agent ships data over DNS using only `socket(SOCK_DGRAM)+sendto` to `:53` → **all legitimate syscalls → no eBPF hook fires**. eBPF is blind to malice done with "good" syscalls.
- Two structural caveats:
  - **Network IP-block is reactive/bypassable** — Project 1's alias trick; NAT/proxy generalize it.
  - **The detector is itself a risk** — a misclassified `bpf_send_signal(9)` is a self-inflicted DoS.
- **Root cause remains:** the SSTI on `:9999` and running as **root** were never fixed — Project 1 only succeeded because both held.

**Speaker script**
> 「接下來講比較誠實的部分。把 Project 1 那條鏈再看一次，有兩個階段我們其實沒守住：
> 第一，SSTI 那個入口我們**從頭到尾沒偵測到**，我們只抓它生出來的 agent，沒有 WAF 門就一直開著；
> 第二，他最後的外洩走 DNS，用的全是正常 syscall——`socket`、`sendto` 打到 53 port，
> 我們一個 hook 都不會響，eBPF 對『用好的 syscall 做壞事』是瞎的。
> 另外兩個風險：換 IP 就破網路層（Project 1 就這樣做的）；還有我們自己的偵測器只要誤判一次，
> 那一發 kill 就等於自己把服務弄掛。而最根本的——`:9999` 那個 SSTI 跟用 root 跑，
> Project 1 之所以會成功，就是因為這兩件事一直都在，而我們從頭到尾沒修。」

**Screenshot / Visual**
- Report **Table 1 (`tab:coverage`)** 的 **Gap** 列（T1190 / T1048.003）反白標紅。
- *(對照)* Project 1 PDF Fig 6c/6d「Reassembled loot / passwd head」= 我們沒擋下來的外洩結果。

---

## S9 — Resolution (合): Lessons & hardening — closing each gap (0:45)

**Slide**
- **Exfil gap →** enumerating "bad" syscalls can't see malice in "good" ones → add a **different sensor**: egress/DNS analytics (entropy, query volume), not another syscall hook
- **SSTI entry →** patch the template injection + put a **WAF** in front of `:9999` → so the kernel layer is a **backstop, not the only wall**
- **Drop root →** Project 1 ran as root; least-privilege shrinks every downstream stage's blast radius
- **False-positive/DoS risk →** move from single-signal kills to **scoring** (correlate `connect` + `dup2` + new-socket) → auto-kill only on high scores, else **quarantine**

**Speaker script**
> 「每個缺口都有對應的解法，而且都對著 Project 1 剛剛那兩個破口：
> 外洩那段要靠 DNS 流量分析這種**另一種感測器**——看查詢量、看亂度，不是再加 syscall hook；
> 入口要把 SSTI 修掉、在 `:9999` 前面加一道 WAF；還有 Project 1 是用 root 跑的，
> 降權限可以把後面每一步的影響範圍都縮小。至於誤判風險，把『單一訊號就殺』改成『**看分數**』，
> 分數夠高才殺、不然先隔離。最重要的是——把入口補起來，讓 kernel 這層回到它該有的位置：
> 是**最後一道後援**，而不是唯一一道牆。」

---

## S10 — Resolution (合): Closing (0:15)

**Slide**
- **Project 1 succeeded because only one layer was live, and it was bypassable.**
- Defense-in-depth is a continuous process: every layer is expected to fail against some phase → security is making sure **the next layer is already watching that phase**.

**Speaker script**
> 「一句話收尾：Project 1 會被打穿，是因為那次只有一層在線、而且那層可以被繞。
> 縱深防禦是一個持續的過程——kill chain 上每一層都會被某一階段繞過，
> 真正重要的是，下一層、下一個感測器，有沒有已經在盯著那個破口。」

**Screenshot / Visual (optional)**
- Report **「attack–defense rounds」(`fig:rounds`)** 當收尾全景（綠 / 琥珀 / 紅）。

---

## Q&A 備答（對應 5 分鐘 QA）

> 老師可能追問的點，先備好一句話答案（都對得回投影片或 Project 1 正式檔）。

| 可能問題 | 一句話回答 | 對應 |
|---|---|---|
| 「Project 1 不是已經打穿了？你們擋什麼？」 | 那次只有網路層在線、eBPF out of scope；我們把 kernel 層補上去，示範它在 Install/C2 攔下整條鏈。 | S1/S6 |
| 「為什麼 SSTI 本身不擋？」 | 範圍在「進來之後」的偵測；入口屬 WAF/應用層修補，S9 列為首要 hardening、S8 標 Gap。 | S8/S9 |
| 「Project 1 沒有 reverse shell，你 S7 在講什麼？」 | 誠實標註是「攻擊者的下一步演化」+ 我們自己 R5 驗過；放這頁是示範縱深、不是宣稱 Project 1 做過。 | S7 |
| 「eBPF 殺錯怎麼辦？」 | 只在最高可信度訊號 enforce（execve `/proc/fd`、ICMP+memfd 關聯），其餘只 alert；S9 提 scoring+隔離降誤判。 | S6/S9 |
| 「DNS 外洩為什麼漏？」 | 只用合法 syscall（`socket SOCK_DGRAM`+`sendto`），syscall 列舉式偵測本質看不到 → 要 egress/DNS 分析。 | S8/S9 |
| 「cold start（防禦比攻擊晚開）呢？」 | `/proc` 掃描器補抓已在跑的 `python3 /proc/<pid>/fd/<N>` agent。 | S6 |
| 「IP 封鎖能擋多久？」 | 設計上預期被 alias 繞過（Project 1 就這樣破的）；任務是給訊號買時間，真正攔截在行為層。 | S4/S2 |

---

## Asset checklist

**Code screenshots（藍隊程式碼）**
| Slide | Kill-chain phase | File | Lines | What it shows |
|---|---|---|---|---|
| S3 | Recon | `target/honeypot.py` | 30–36 | fake SSH banner / fake rejection |
| S3 | Recon | `target/honeypot.py` | 50–78 | send banner + write `trap.log` |
| S4 | IP-bypass | `blue_team/blue_mdr_network.py` | 47–52 | `iptables -I INPUT 1 ... DROP` |
| S4 | IP-bypass | `blue_team/blue_mdr_network.py` | 87–119 | tail `trap.log`, block new IPs |
| S6 | Install | `blue_team/blue_ebpf_mdr_v2.py` | 106–116 | memfd hook (alert-only / taint) |
| S6 | Install | `blue_team/blue_ebpf_mdr_v2.py` | 149–178 | `execve` argv `/proc/fd` → kill |
| S6 | C2 (ICMP) | `blue_team/blue_ebpf_mdr_v2.py` | 196–211 | raw ICMP + correlation → kill |
| S7 | C2 (revshell, R5) | `blue_team/blue_ebpf_mdr_v2.py` | 279–300 | `dup2` bitmask → `0x07` kill |
| S7 | C2 (revshell, R5) | `blue_team/blue_ebpf_mdr_v2.py` | 454–457 | load-time `bpf_send_signal(9)` injection |

**Report figures / tables（藍隊報告 `BLUE_TEAM_REPORT.pdf`）**
| Slide | Asset | Section / label |
|---|---|---|
| S2 / S8 | Table 1「Detection coverage」(kill-chain ↔ control map) | `tab:coverage` |
| S2 | Figure「Defense-in-depth」 | `fig:did` |
| S5 | Figure「eBPF pipeline」 | `fig:pipeline` |
| S7 | Figure「Reverse-shell bitmask state machine」 | `fig:dup2` |
| S10 | Figure「attack–defense rounds」 | `fig:rounds` |

**Project 1 attack figures（`Network_Security_Hands_on_2_1.pdf`，攻擊側對照）**
| Slide | Project 1 figure | Shows |
|---|---|---|
| S1 | §4 Attack-Chain table | the validated end-to-end path |
| S3 | Fig 2a | honeypot triggered |
| S4 | Fig 2b | IP-alias bypass |
| S6 | Fig 5a / 5c | ICMP beacon + interactive cmds (what we kill before it appears) |
| S8 | Fig 6c / 6d | exfiltrated loot (the gap we don't close) |

---

> ### ✅ 書面報告已同步對齊（2026-06-12）
> `BLUE_TEAM_REPORT.tex` 已一併對齊 Project 1：abstract / threat-model（加 [P1] vs [anticipated] 標記 + 真實路徑）/
> coverage table（T1571·dup2·cron 移到 † anticipated 分隔線下 + 註腳）/ `fig:rounds`（R5 標 †、R6 改「DNS exfil」去掉
> cron）/ round-by-round 敘事（R5=anticipated、R6=`nohup`+HTTP agent over DNS）/ limitations「Persistence」「What it
> doesn't stop」/ conclusion 全部改為事實正確。**⚠ PDF 需重編**（本機無 TeX；用 Overleaf 重 build `BLUE_TEAM_REPORT.pdf`）。
