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
> 「我們這組的 Project 1，從偵察一路打到資料外洩，整條攻擊鏈都打穿了。今天我站防守方，沿同一條鏈
> 走一次，講兩件事：那次為什麼守不住，以及把我們的 kernel 層補上去之後，攻擊會在哪一步被擋下來。」

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
> 「我們要守的就是 Project 1 這條鏈，原封不動。攻擊者先掃 port，找到真正的目標 `:9999`，踩了一下蜜罐、
> 再換一個 IP 繞過封鎖，然後用 SSTI 打進來，在記憶體裡 fileless 載入，開一條走 ICMP 的 C2，下指令，
> 最後把 `passwd`、`shadow` 帶出去。這裡有一點很關鍵：Project 1 那次只有網路層在線上，eBPF 不在他們的
> 範圍裡——這在他們報告也寫了。所以網路層一被繞過，SSTI 之後整段就沒人擋、一路做完。我們今天就是把缺的這一層補回來。」

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

- **Layer 1 (network):** cheap, earliest signal — but **bypassable** (Project 1 bypassed it)
- **Layer 2 (kernel/eBPF):** the real enforcer — acts on **behavior** (IP-alias irrelevant) → **re-takes control at Install/C2**

**Speaker script**
> 「這張表把整條鏈攤開，每個階段配一個防禦，並標出哪些真的擋得住、哪些只是記一筆、哪些沒守住。
> Project 1 被打穿的點就在 IP 封鎖這一列：它是反應式的，擋的是來源 IP，攻擊者換一個 IP 就繞過去了。
> 第二層 eBPF 不看 IP、看行為，所以在 Install 跟 C2 這兩步把控制權接回來——這也是繞過之後，
> 攻擊者第一個會碰到 kernel 的動作。後面幾頁就照這張表，一階段一階段往下走。」

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
> 「第一步是偵察。Project 1 一開始就掃 port，掃到 `:2222` 跟 `:9999`。我們在 `:2222` 放一個假的 SSH 當
> 誘餌，回給它的 banner 跟真的 OpenSSH 版本字串一模一樣，`nmap -sV` 分不出來。蜜罐的好處是訊號乾淨：
> 正常服務不會有人連 `:2222`，所以只要有人連上來，幾乎就能確定是在踩點。Project 1 那次是從 `.14` 連進來的，
> 我們把這個 IP 寫進 `trap.log`，這就是交給下一個元件的情報。」

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
> 「蜜罐一抓到新的 IP，我們不到一秒就插一條最高優先權、擋掉所有 port 的 DROP 規則，那個 IP 整台就被切掉。
> 但這也是它的罩門：它擋的是來源 IP，而來源 IP 是攻擊者自己控制的。Project 1 就是在這裡破的——加一個
> alias IP `.15`，換一個來源身分，又連回 `:9999`。所以這一層被繞過不是 bug，是設計上就預期的：它負責給
> 最早的訊號、爭取時間，攔截交給第二層。到這裡，網路層在 Project 1 就出局了。」*（埋伏筆，接 S6 的「接管」）*

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
> 「為什麼第二層用 eBPF？因為 Project 1 繞過網路層之後，接下來每一步——SSTI 生出來的 loader、`memfd`、
> `execve`、ICMP——全部都會經過 kernel，而 eBPF 就掛在那裡。它不看 IP，所以換 IP 那招對它沒用；
> 它直接看得到 fileless 的 syscall 參數，磁碟掃不到的它看得到；而且它掛在 syscall 的進入點，
> 能在危險動作真的發生之前就攔下來。」

**Screenshot / Visual**
- Report **Figure「eBPF pipeline」(`fig:pipeline`)** (C → BCC → bytecode → verifier → JIT → tracepoint → perf buffer).

---

## S6 — Development climax (承): Killing the fileless ICMP C2 (1:45)

> **Kill-chain phase:** Install (T1620) + C2 (T1095) · **this is Project 1's *actual* C2 — and where we re-take control**

**Slide**
- Project 1's C2 path: `memfd_create → write agent → fork → execve /proc/fd → ICMP beacon`
- `memfd_create` → **alert + taint** (benign uses → don't kill)
- `fork` → **taint inherited** by children
- `execve` argv = `/proc/<pid>/fd/<N>` → **KILL** ← *no agent → no beacon → no exfil*
- raw ICMP socket + memfd taint → **KILL** (Project 1's exact C2)
- Cold-start: a `/proc` scanner kills an already-running agent
- *Enforce only on the highest-confidence signal; alert on the rest*

**Speaker script**
> 「這一頁擋的就是 Project 1 真正用的那條 C2。流程是：SSTI 打進來後，`memfd_create` 在記憶體開一個檔，
> 把 agent 寫進去，fork 之後用 `/proc/<pid>/fd` 執行，再透過 ICMP 回連。我們不會在 `memfd` 這步就殺，
> 因為它本身有正常用途，先把這個行程標記起來，連它 fork 出來的子行程一起標。真正動手是在 `execve` 看到
> argv 指向 `/proc/fd` 的時候，直接 kill——agent 還沒跑起來，就沒有 beacon、沒辦法下指令，後面也就沒得外洩。
> 那條 ICMP C2 單看只會記一筆，但只要它跟前面 memfd 的標記對得上，一樣殺。另外，如果我們比 agent 晚啟動，
> 有一支 `/proc` 掃描器會把已經在跑的補抓回來殺掉。網路層在第四步出局，kernel 層就在這一步把控制權接回來。」

**Screenshot / Visual** — code: `blue_team/blue_ebpf_mdr_v2.py`
- **L106–116** — memfd hook (alert-only / taint)
- **L149–178** — `execve` argv `/proc/fd` check → kill
- **L196–211** — raw ICMP + correlation → kill
- *(對照)* Project 1 PDF Fig 5a「Beacon received」/ Fig 5c「cat /etc/hostname, ls」= 我們要在 beacon 出現前就殺掉的東西

---

## S7 — Development (承): The anticipated reverse-shell evasion (1:15)

> **Kill-chain phase:** C2 evasion · ⚠ **beyond Project 1 (it used ICMP); validated in blue round R5 as the attacker's natural next move**

**Slide** — *無條列文字,三張圖:概念圖 + 兩張程式碼圖(內容靠口語帶)*
- **圖①(概念):** report **「Reverse-shell bitmask state machine」(`fig:dup2`)** — `000 → 001 → 011 → 111 → SIGKILL`
- **圖②(執行期偵測):** `blue_ebpf_mdr_v2.py` **L279–300** — `dup2` per-PID bitmask → `0x07` 確認;確認點只留一個 `__KILL_DUP2__` **佔位符**
- **圖③(載入期注入):** `blue_ebpf_mdr_v2.py` **L452–466** — `--kill` 時把 `__KILL_DUP2__` 換成 `e.killed=1; bpf_send_signal(9);`,monitor 時換成空字串(同一份 C source 共用)
- *(建議在圖上保留一行小字當誠實標註)* **Scope: not Project 1's C2 (it used ICMP) — anticipated next move, validated in round R5**

**Speaker script**（無條列,照「圖①概念 → 圖②執行期 → 圖③載入期注入」三段走)
> 「先講範圍,免得跟 Project 1 混在一起:Project 1 用的是 ICMP,沒有用 reverse shell。但防守方要先想下一步——
> 攻擊者知道我們在盯 memfd 跟 ICMP,最自然的閃法就是改用純 TCP 的 reverse shell,前面那四個 hook 完全不會響。
> 這個情境我們自己在 R5 那一回合驗過。
>
> **那我們怎麼抓這條純 TCP 的 reverse shell?先看圖①這張狀態機**。原理是:任何 reverse shell 都一定要把 stdin、stdout、stderr
> 這三個標準輸出入接到同一條 socket,才能在遠端拿到一個能互動的 shell。所以我們對每個行程記一個 3-bit 的 bitmask——就是圖上
> `000`、`001`、`011`、`111` 這四個圈——每被 `dup2` 接走一個 fd 就點亮一個 bit。畫面上是照 0、1、2 的順序畫,但實際順序不拘;
> 只要三個全亮、湊成 `111`(也就是 `0x07`),就確認是 reverse shell——對應圖最後那個紅框 SIGKILL。
>
> **圖②就是圖①這張狀態機,在 kernel 裡實際跑的程式碼**。最上面 hook 掛在 `sys_enter_dup2`,也就是 `dup2` 的進入點;一進來先擋雜訊
> ——要接的 fd 大於 2 就直接 return,只留 stdin、stdout、stderr 這三個;接著在這個行程自己的 bitmask 上把對應的 bit 設起來
> (`new_mask |= (1 << newfd)`),累積到 `new_mask == 0x07` 就確認。重點在確認之後那一行——你會看到圖①那個 SIGKILL 在程式碼裡
> **並沒有被寫死**,只放了一個孤零零的 `__KILL_DUP2__` 空位。為什麼留空、不直接殺?答案在圖③。
>
> **圖③就是在填圖②那個空位的程式碼**,分成兩種模式。預設不加 `--kill` 是 monitor 模式,空位填空字串,所以就算確認到 reverse shell 也只回報、不殺;
> 加 `--kill` 是 enforce 模式,空位填 `bpf_send_signal(9)`,確認的當下就把那個行程殺掉。
> 為什麼要在啟動時就編成兩份、而不是寫一份用旗標在執行時決定?因為 `bpf_send_signal` 送的是 SIGKILL,殺了就回不來,一旦誤判就是殺到正常行程。
> 如果用旗標,kill 那行始終都在程式裡、只是被條件擋著,旗標判斷錯就會誤殺;編成兩份的話,monitor 那份編出來根本沒有 kill 這行,從源頭就不會誤殺。
> 補充一下 `else` 為什麼要存在:`__KILL_*__` 這些標記本身不是合法 C,只要有一個沒換掉就編譯不過,所以 monitor 模式不能直接跳過,`else` 一定要把每個殺點都換成空字串,才編得出一份合法、但完全不帶 kill 的程式。
> 所以實務上是先跑 monitor、確認偵測沒有誤判,再切 `--kill`。兩份的偵測邏輯一樣,差別只在 kill 那行有沒有被編進去。
>
> 收尾兩點:第一,它看行為不看 port,走 80、443 一樣擋,`dup3` 也一起掛了;第二,這頁講的是縱深——
> 就算攻擊者進化、跳過前面所有 hook,我們的下一個感測器已經先在這裡等它了。」

**Screenshot / Visual** — *本頁三張圖*
- **圖①｜Figure:** report **「Reverse-shell bitmask state machine」(`fig:dup2`)** (`000 → 001 → 011 → 111 → SIGKILL`)
- **圖②｜Code(執行期偵測):** `blue_team/blue_ebpf_mdr_v2.py` **L279–300** — `sys_enter_dup2` 的 per-PID bitmask → `0x07` 確認;確認點留 `__KILL_DUP2__` **佔位符**
- **圖③｜Code(載入期注入):** 同檔 **L452–466** — `--kill` 時 `__KILL_DUP2__` → `e.killed = 1; bpf_send_signal(9);`,monitor 時 → 空字串(同一份 C source,兩模式共用偵測碼)

---

## S8 — Turn (轉): Defense scoreboard — every stage we took control of (1:15)

> **Kill-chain stages we enforce:** Honeypot-trigger (IP block) · Install (`execve` kill) · C2 (ICMP kill) · reverse-shell (`dup2/dup3` kill)

**Slide** — *戰果 scoreboard(coverage 表在下一頁)*
- **Network — honeypot-trigger:** new IP → `iptables` DROP in **< 1 s** (cuts all ports at once)
- **Install:** `execve` argv = `/proc/<pid>/fd/<N>` → **kill** — the fileless agent never runs
- **C2 — Project 1's actual C2:** raw ICMP socket correlated with `memfd` taint → **kill**
- **Cold-start:** a `/proc` scanner kills an agent already running before we attached
- **Reverse-shell (anticipated):** `dup2/dup3` → all three fds set (`0x07`) → **kill** — the attacker's next move, pre-covered
- **Outcome:** Project 1's fileless C2 **died before it beaconed** — every behavioral stage we own ends in **Enforce / kill**

**Speaker script**
> 「這頁把我們守住的戰果收一收。網路層先把來源 IP 封掉,不到一秒切斷所有 port。進到 kernel:`execve` 從
> `/proc/fd` 起來就殺,Project 1 的 fileless agent 還沒跑就被擋掉;那條 ICMP C2——也就是 Project 1 真正用的
> C2——跟 memfd 的標記一對上也殺;就算我們比 agent 晚啟動,`/proc` 掃描器也會把已經在跑的補殺掉。最後是
> reverse-shell 的 fd hijack,`dup2/dup3` 三個 fd 湊成 `0x07` 就殺,連攻擊者下一步可能改用的純 TCP reverse shell 都先備好。
> 從網路一路到 kernel,Project 1 真正用來打穿的那條 C2,就是在這裡被接管、被殺掉的。
> 下一頁這張 coverage 表,綠色的 Enforce 列就是剛剛這幾個戰果的彙整。」

**Screenshot / Visual** — *本頁純文字;coverage 表放下一頁*
- **下一頁主圖:** Report **Table 1 (`tab:coverage`)**,截到 **reverse-shell fd hijack(`dup2/dup3`)** 這列;把 **Enforce / kill 列**(iptables block、execve、ICMP、dup2)上綠 highlight,視線集中在戰果。
- *(提醒)* 截到那列會一併帶到中間兩個 **Gap 列(T1190 SSTI、T1048.003 DNS)**;不想露出「Gap」就把那兩列灰掉、或只 highlight Enforce 列。**不要**放外洩 loot 圖。

---

## S9 — Resolution (合): Hardening roadmap — the layers we'd add next (0:45)

**Slide**
- **Egress sensor →** enumerating "bad" syscalls can't see malice in "good" ones → add a **different sensor**: egress/DNS analytics (entropy, query volume), not another syscall hook
- **App-layer fix →** patch the template injection + put a **WAF** in front of `:9999` → the kernel layer stays a **backstop, not the only barrier**
- **Drop root →** the **`:9999` service itself** ran as root, so the SSTI RCE inherited root → run it under a **dedicated unprivileged account** (systemd `User=` / `NoNewPrivileges` / drop capabilities) so any RCE lands non-root — shrinking every downstream stage's blast radius
- **Confidence scoring →** move from single-signal kills to **scoring** (correlate `connect` + `dup2` + new-socket) → auto-kill only on high scores, else **quarantine**

**Speaker script**
> 「在現在守住的基礎上，接下來會再補四塊。第一，加一個不一樣的感測器——DNS 流量分析，看查詢量、看子網域的
> 亂度，因為藏在合法 syscall 裡的外洩，syscall hook 本來就看不到，要從網路行為這邊看。第二，入口在應用層補:
> 把 template injection 修掉、在 `:9999` 前面加一道 WAF，讓 kernel 這層當後援，而不是唯一的防線。第三，降權——
> 降的是我們自己 `:9999` 那個服務的權限:它當初是用 root 跑的，所以 SSTI 一打進來就直接拿到 root。把它改用一個
> 專用的低權限帳號跑(systemd 設 `User=`、`NoNewPrivileges`、拿掉 capability),之後就算被 RCE，拿到的也只是個
> 沒權限的 shell，後面能造成的影響就小很多。第四，把『單一訊號就殺』改成多訊號
> 評分——`connect`、`dup2`、新 socket 關聯起來算分數，分數夠高才自動殺，不夠就先隔離，把誤判壓下去。
> 這四塊一起做，等於把縱深從現在的兩層再往外推一層。」

---

## S10 — Resolution (合): Closing (0:15)

**Slide**
- **Project 1 succeeded because only one layer was live, and it was bypassable.**
- Defense-in-depth is a continuous process: every layer is expected to fail against some phase → security is making sure **the next layer is already watching that phase**.

**Speaker script**
> 「Project 1 會被打穿，說到底就是那次只有一層在線上，而且那層能被繞過。縱深防禦是一個持續的過程——
> kill chain 上每一層都會被某個階段繞掉，真正重要的是下一層、下一個感測器，有沒有已經在盯著那個階段。」

**Screenshot / Visual (optional)**
- Report **「attack–defense rounds」(`fig:rounds`)** 當收尾全景（綠 / 琥珀 / 紅）。

---

## Q&A 備答（對應 5 分鐘 QA）

> 老師可能追問的點，先備好一句話答案（都對得回投影片或 Project 1 正式檔）。

| 可能問題 | 一句話回答 | 對應 |
|---|---|---|
| 「Project 1 不是已經打穿了？你們擋什麼？」 | 那次只有網路層在線、eBPF out of scope；我們把 kernel 層補上去，示範它在 Install/C2 攔下整條鏈。 | S1/S6 |
| 「為什麼 SSTI 本身不擋？」 | kernel 層守的是「進來之後」的執行/C2;入口屬應用層、WAF 的範圍,S8 定位為其他層負責、S9 列為首要 hardening。 | S8/S9 |
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
| S7 | C2 (revshell, R5) | `blue_team/blue_ebpf_mdr_v2.py` | 452–466 | load-time `__KILL_DUP2__` injection (`--kill` vs monitor) |

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
