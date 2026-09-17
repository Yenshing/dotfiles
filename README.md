# 個人開發環境與工作流設定備份 (IT-Settings)

本目錄備份了 WezTerm 終端機、Windows 端 Herdr、WSL 端 Herdr、以及 WSL Zsh 的完整設定與多 Agent 配額監控整合工具（CodexBar）。未來若更換電腦或重灌系統，可依照本文件指引快速一鍵還原完整工作流模式。

---

## 目錄架構

```text
IT-Settings/
├── README.md                 # 完整還原與設定說明文件
├── restore-windows.ps1       # [一鍵還原] Windows 端設定 (WezTerm, Herdr, codexbar)
├── restore-wsl.sh            # [一鍵還原] WSL 端設定 (Zsh, p10k, Herdr, codexbar)
├── wezterm/
│   ├── .wezterm.lua          # WezTerm 主設定檔 (雙 Tab 啟動、Solarized 主題、Launch Menu)
│   └── window_size.json      # WezTerm 視窗預設位置與尺寸紀錄
├── herdr/
│   ├── windows/
│   │   ├── config.toml       # Windows Herdr 設定 (tmux 鍵位、右側配額列、prefix+q)
│   │   ├── scripts/
│   │   │   └── herdr-quota.ps1 # Windows 端 CodexBar (監控 Codex 與 Agy)
│   │   └── bin/
│   │       ├── codexbar      # Windows bash 入口
│   │       ├── codexbar.cmd  # Windows cmd 入口
│   │       └── codexbar.ps1  # Windows powershell 入口
│   └── wsl/
│       ├── config.toml       # WSL Herdr 設定 (tmux 鍵位、右側配額列、prefix+q)
│       └── scripts/
│           └── herdr-quota.py # WSL 端 CodexBar (監控 Claude 與 Agy)
├── windows/
│   ├── .bashrc               # Git Bash 設定 (含 Herdr Live CWD 自動更新 workspace 與 PATH)
│   └── Microsoft.PowerShell_profile.ps1 # PowerShell 設定 (含 Herdr Live CWD 自動更新)
└── wsl/
    ├── .zshrc                # WSL Zsh 設定 (Oh My Zsh, 外掛配置, PATH)
    ├── .zshenv               # WSL Zsh 環境變數設定 (~/.local/bin PATH)
    ├── .p10k.zsh             # Powerlevel10k 提示字元美化配置
    └── install_zsh.sh        # Zsh + Oh My Zsh + 必備外掛安裝腳本
```

---

## 新電腦快速還原步驟

### 第一步：基礎工具安裝（在新電腦上）

1. **安裝 WezTerm**：
   ```powershell
   winget install wez.wezterm
   ```
2. **安裝 Nerd Font**（讓 Powerlevel10k 與 Herdr 圖示正常顯示）：
   * 建議安裝 **MesloLGS NF** 或 **JetBrainsMono Nerd Font**。
3. **啟用 WSL 2 並安裝 Ubuntu**：
   ```powershell
   wsl --install -d Ubuntu
   ```
4. **安裝 Herdr**：
   * **Windows**：從 [herdr.dev](https://herdr.dev) 下載並安裝獨立套件。
   * **WSL**：在 WSL 中執行官方安裝腳本（`curl -fsSL https://herdr.dev/install.sh | bash`）。

---

### 第二步：還原 Windows 端設定

以 PowerShell 執行還原腳本：
```powershell
# 進入備份目錄
cd ~/Documents/Personal/IT-Settings

# 執行還原腳本
powershell -ExecutionPolicy Bypass -File .\restore-windows.ps1
```

> **還原內容**：
> * `~/.wezterm.lua`：啟動時預設自動開啟 `Windows Herdr` 與 `WSL Herdr` 雙分頁、視窗自適應記憶。
> * `~/AppData/Roaming/herdr/`：Herdr 鍵位與 `herdr-quota.ps1` 監控腳本。
> * `~/bin/codexbar*`：全域 `codexbar` CLI 指令，並自動加入使用者環境變數 PATH。
> * `~/.bashrc` 與 PowerShell Profile：注入 Herdr Live CWD (OSC 9;9) 整合，讓 `cd` 到包含 `.git` 的資料夾時自動辨識並即時更新 workspace。

---

### 第三步：還原 WSL 端設定

在 WSL (Ubuntu) 終端機中執行還原腳本：
```bash
# 進入 Windows 備份目錄在 WSL 的掛載點
cd /mnt/c/Users/cyc76/Documents/Personal/IT-Settings

# 執行還原腳本
bash ./restore-wsl.sh
```

> **還原內容**：
> * 自動檢測並可一鍵安裝 Oh My Zsh、Powerlevel10k 及外掛（`zsh-autosuggestions`, `zsh-syntax-highlighting`, `zsh-z`）。
> * 還原 `~/.zshrc`、`~/.zshenv` 與 `~/.p10k.zsh`。
> * 還原 `~/.config/herdr/config.toml` 與 `~/.config/herdr/scripts/herdr-quota.py`。
> * 建立 `~/.local/bin/codexbar` 軟連結。

---

### 第四步：各 Agent 登入授權

* **Claude Code (WSL)**：
  ```bash
  claude
  ```
  完成網頁 OAuth 登入後，`codexbar` 即可自動讀取 `~/.claude/.credentials.json` 監控 5h 與 7d 限額。
* **Google Antigravity / Agy (Windows & WSL)**：
  ```bash
  agy
  ```
  登入後 `agy --print /usage` 即可提供即時 Gemini 與第三方模型限額。
* **OpenAI Codex (Windows)**：
  ```powershell
  codex
  ```
  登入後即可於 Windows Herdr 監控用量。

---

## 常用操作快速鍵

### WezTerm 視窗操作
| 快速鍵 | 功能 |
| :--- | :--- |
| <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>1</kbd> | 切換至 **Windows Herdr** 分頁 |
| <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>2</kbd> | 切換至 **WSL Herdr** 分頁 |
| <kbd>Ctrl</kbd> + <kbd>Tab</kbd> / <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>Tab</kbd> | 上一個 / 下一個 WezTerm 分頁 |
| 右鍵點擊分頁列 <kbd>+</kbd> 號 | 快速選單開啟新的 Windows Herdr 或 WSL Herdr |

### Herdr 快捷鍵 (Prefix: `Ctrl+a`)
| 快速鍵 | 功能 |
| :--- | :--- |
| <kbd>Ctrl+a</kbd> 後按 <kbd>q</kbd> | **開啟 CodexBar AI Quota 全螢幕彩色儀表板** |
| <kbd>Ctrl+a</kbd> 後按 <kbd>b</kbd> | 展開 / 收合 Agent 側邊欄（顯示即時 `$quota` 與 `$context`） |
| <kbd>Ctrl+a</kbd> 後按 <kbd>c</kbd> | 在當前工作區開新 Tab |
| <kbd>Ctrl+a</kbd> 後按 <kbd>&#124;</kbd> | 垂直分割 Pane |
| <kbd>Ctrl+a</kbd> 後按 <kbd>-</kbd> | 水平分割 Pane |
| <kbd>Ctrl+a</kbd> 後按 <kbd>z</kbd> | Zoom / 放大當前 Pane |
| <kbd>Ctrl+a</kbd> 後按 <kbd>Shift+r</kbd> | 重新載入 Herdr 設定檔 |

### CodexBar CLI 查詢指令
| 終端機指令 | 說明 |
| :--- | :--- |
| `codexbar` | 查看當前環境的所有 AI Agent 用量與目前 Session Context |
| `codexbar context` (`ctx`) | 查看當前各 Agent Session 的 Context Window 與 Token 消耗量 |
| `codexbar agy` | 僅查看 Antigravity (Gemini / Claude / GPT) 用量與 Context |
| `codexbar claude` | 僅查看 Anthropic Claude 用量與 Context（WSL 端） |
| `codexbar codex` | 僅查看 OpenAI Codex 用量與 Context（Windows 端） |
| `codexbar dash` | 終端內開啟互動式 ASCII 彩色儀表板（含 Quota、Context 與 Pane 狀態） |
| `codexbar status` | 輸出單行狀態字串（含聚焦 Agent Context）並更新 Herdr Pane Metadata |
| `codexbar refresh` | 略過快取直接向 API 重新擷取最新數據 |
