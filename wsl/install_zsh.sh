#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing zsh, git, curl, fontconfig..."
sudo apt-get update
sudo apt-get install -y zsh git curl fontconfig

ZSH_CUSTOM="${HOME}/.oh-my-zsh/custom"

echo "==> Installing Oh My Zsh (unattended)..."
if [ ! -d "${HOME}/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "Oh My Zsh already installed, skipping."
fi

echo "==> Installing Powerlevel10k theme..."
if [ ! -d "${ZSH_CUSTOM}/themes/powerlevel10k" ]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM}/themes/powerlevel10k"
else
  echo "powerlevel10k already installed, skipping."
fi

echo "==> Installing zsh-autosuggestions..."
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
else
  echo "zsh-autosuggestions already installed, skipping."
fi

echo "==> Installing zsh-syntax-highlighting..."
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
  git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
else
  echo "zsh-syntax-highlighting already installed, skipping."
fi

echo "==> Installing zsh-z..."
if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-z" ]; then
  git clone --depth=1 https://github.com/agkozak/zsh-z "${ZSH_CUSTOM}/plugins/zsh-z"
else
  echo "zsh-z already installed, skipping."
fi

echo "==> Configuring ~/.zshrc..."
ZSHRC="${HOME}/.zshrc"

if grep -q '^ZSH_THEME=' "$ZSHRC"; then
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
else
  echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSHRC"
fi

if grep -q '^plugins=' "$ZSHRC"; then
  sed -i 's|^plugins=.*|plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-z)|' "$ZSHRC"
else
  echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-z)' >> "$ZSHRC"
fi

echo "==> Setting zsh as default shell..."
ZSH_PATH="$(command -v zsh)"
if [ "${SHELL:-}" != "$ZSH_PATH" ]; then
  sudo chsh -s "$ZSH_PATH" "$(whoami)"
fi

echo ""
echo "=================================================================="
echo "完成!請關閉並重新開啟終端機(或執行 'exec zsh')來套用變更。"
echo "首次進入 zsh 時,Powerlevel10k 會自動啟動設定精靈 (p10k configure)。"
echo "建議先安裝 Nerd Font (例如 MesloLGS NF) 讓圖示正確顯示:"
echo "  https://github.com/romkatv/powerlevel10k#manual-font-installation"
echo "=================================================================="
