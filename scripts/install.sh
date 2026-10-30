#!/bin/sh
# Сборка HyperLLM.app в ~/Applications, установка mlx-lm и подключение Hyper-плагина локально.
set -eu
cd "$(dirname "$0")/.."
ROOT=$PWD
APP="$HOME/Applications/HyperLLM.app"

command -v uv >/dev/null || { echo "Нужен uv: brew install uv"; exit 1; }
command -v jq >/dev/null || { echo "Нужен jq: brew install jq"; exit 1; }
[ -x "$HOME/.local/bin/mlx_lm.server" ] || uv tool install --python 3.12 mlx-lm

osascript -e 'quit app id "com.hukopo.hyperllm"' 2>/dev/null || true
while pgrep -qf 'HyperLLM.app/Contents/MacOS/HyperLLM'; do sleep 0.2; done  # иначе open попадёт в закрывающийся экземпляр
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp app/Info.plist "$APP/Contents/"
cp app/guard.sh "$APP/Contents/Resources/"
swiftc -O -target "$(uname -m)-apple-macos13" app/HyperLLM.swift -o "$APP/Contents/MacOS/HyperLLM"
codesign -s - --force "$APP"

ZSH_PLUGINS="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
if [ -d "$ZSH_PLUGINS" ] && [ ! -d "$ZSH_PLUGINS/zsh-autosuggestions" ]; then
  git clone -q --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_PLUGINS/zsh-autosuggestions"
fi

mkdir -p "$HOME/.hyper_plugins/local"
ln -sfn "$ROOT" "$HOME/.hyper_plugins/local/hyper-llm-complete"

open "$APP"
cat <<'EOF'
Готово. Осталось:
  1. ~/.hyper.js:  localPlugins: [..., "hyper-llm-complete"]
  2. ~/.zshrc:     zsh-autosuggestions в plugins=(...) и после oh-my-zsh:
                   [[ -n $HYPER_LLM_ZSH ]] && source $HYPER_LLM_ZSH
  3. Перезапустить Hyper.
EOF
