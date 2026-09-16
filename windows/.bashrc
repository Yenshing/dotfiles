# Set UTF-8 locale
export LANG="zh_TW.UTF-8"
export LC_ALL="zh_TW.UTF-8"

# Ensure coreutils (ls, find, etc.) display non-ASCII characters literally without octal escaping
export QUOTING_STYLE="literal"
alias ls='ls -F --color=auto --show-control-chars -N'
alias ll='ls -la'
alias gst='git status'

# User local bin (codexbar, etc.)
export PATH="$HOME/bin:$HOME/AppData/Local/agy/bin:$PATH"

# Herdr / Terminal Live CWD integration (OSC 9;9)
# 自動向 Herdr 回報目前工作目錄，讓 Windows 端的 Herdr 能在 cd 切換目錄時即時更新 workspace
__herdr_osc_cwd() {
    local winpath
    if command -v cygpath >/dev/null 2>&1; then
        winpath=$(cygpath -w "$PWD" 2>/dev/null)
    elif [ -n "$(pwd -W 2>/dev/null)" ]; then
        winpath=$(pwd -W 2>/dev/null)
    else
        winpath="$PWD"
    fi
    printf '\033]9;9;%s\033\\' "$winpath"
}

if [ -n "${PROMPT_COMMAND:-}" ]; then
    if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" =~ "declare -a" ]]; then
        PROMPT_COMMAND=(__herdr_osc_cwd "${PROMPT_COMMAND[@]}")
    elif [[ ! "$PROMPT_COMMAND" =~ "__herdr_osc_cwd" ]]; then
        PROMPT_COMMAND="__herdr_osc_cwd; $PROMPT_COMMAND"
    fi
else
    PROMPT_COMMAND="__herdr_osc_cwd"
fi
