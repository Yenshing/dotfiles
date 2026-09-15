#!/usr/bin/env bash
# ==============================================================================
# 一鍵還原 WSL 端的 Zsh 與 Herdr (含 Claude / Agy CodexBar) 設定檔
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "\033[36m==> 開始還原 WSL 開發環境設定...\033[0m"

# 1. 檢查並詢問是否安裝 Oh My Zsh + Plugins
if [ ! -d "${HOME}/.oh-my-zsh" ]; then
    echo -e "\033[33m[!] 偵測到尚未安裝 Oh My Zsh，是否自動執行安裝環境依賴？ (y/n)\033[0m"
    read -r ans || ans="y"
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        bash "${SCRIPT_DIR}/wsl/install_zsh.sh"
    fi
fi

# 2. 還原 Zsh 與環境變數設定
cp -f "${SCRIPT_DIR}/wsl/.zshrc" "${HOME}/.zshrc"
echo -e "\033[32m[OK] 已還原 ~/.zshrc\033[0m"

cp -f "${SCRIPT_DIR}/wsl/.zshenv" "${HOME}/.zshenv"
echo -e "\033[32m[OK] 已還原 ~/.zshenv\033[0m"

if [ -f "${SCRIPT_DIR}/wsl/.p10k.zsh" ]; then
    cp -f "${SCRIPT_DIR}/wsl/.p10k.zsh" "${HOME}/.p10k.zsh"
    echo -e "\033[32m[OK] 已還原 ~/.p10k.zsh (Powerlevel10k 主題設定)\033[0m"
fi

# 3. 還原 Herdr 設定與 Quota 監控腳本
mkdir -p "${HOME}/.config/herdr/scripts"
cp -f "${SCRIPT_DIR}/herdr/wsl/config.toml" "${HOME}/.config/herdr/config.toml"
echo -e "\033[32m[OK] 已還原 ~/.config/herdr/config.toml\033[0m"

cp -f "${SCRIPT_DIR}/herdr/wsl/scripts/herdr-quota.py" "${HOME}/.config/herdr/scripts/herdr-quota.py"
chmod +x "${HOME}/.config/herdr/scripts/herdr-quota.py"
echo -e "\033[32m[OK] 已還原 ~/.config/herdr/scripts/herdr-quota.py\033[0m"

# 4. 建立 ~/.local/bin/codexbar 軟連結
mkdir -p "${HOME}/.local/bin"
ln -sf "${HOME}/.config/herdr/scripts/herdr-quota.py" "${HOME}/.local/bin/codexbar"
echo -e "\033[32m[OK] 已建立 ~/.local/bin/codexbar 指令連結\033[0m"

# 5. 若 Herdr 正在運行，自動重新載入設定
if command -v herdr >/dev/null 2>&1; then
    if herdr status server 2>/dev/null | grep -q "status: running"; then
        herdr server reload-config >/dev/null 2>&1 || true
        echo -e "\033[32m[OK] Herdr 運行中，已即時 reload-config\033[0m"
    fi
fi

echo -e "\n\033[36m==> WSL 設定還原完成！請執行 'exec zsh' 或重啟終端機即可套用。\033[0m"
