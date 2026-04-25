# Cybersecurity Project — Claude 指引

## Commit 規則
- **不加** `Co-Authored-By` 行
- Commit message 必須帶版本號（如 `v2.3 fix: ...`），不要只用 git hash
- 不要 commit `PROJECT_MAP.md`（已在 .gitignore）
- 不要 commit `docs/RED_TEAM_SLIDES*.md`（已在 .gitignore）

## 回覆語言
- 使用繁體中文

## 專案導航
- 詳細檔案索引見 `PROJECT_MAP.md`（本地用，不進 git）

## 環境
- 雙機架構：Lab 機器（靶機 + 藍軍）+ 攻擊機（紅軍），都是原生 Ubuntu 24.04
- Python 工具透過 venv 執行：`sudo .venv/bin/python3 <script.py>`

## 注意事項
- deploy_agent.sh 使用 HTTP server 方式（v3），不是 base64
- C2 有 15 秒 timeout，長時間指令要用 `nohup ... &` 背景執行
- exfil_agent.py 執行完會自刪（`os.remove(__file__)`）
- **不要在 README 或任何文件的分工表寫組員姓名和學號**，只留 Role 和 Responsibilities
