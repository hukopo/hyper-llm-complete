# Стратегия zsh-autosuggestions: сначала история, потом локальная LLM (HyperLLM на :8765).
# Демон не отвечает — curl падает по таймауту, подсказки только из истории.

(( $+commands[curl] && $+commands[jq] )) || return 0

_zsh_autosuggest_strategy_llm() {
  local buf=$1
  (( ${#buf} < 2 || ${#buf} > 200 )) && return
  # Промпт обрываем на целом слове без хвостового пробела: недописанный токен и пробел
  # в конце сбивают base-модель. Формат «скрипт истории» она продолжает лучше всего.
  local head=${buf%${buf##* }}
  [[ $head =~ '^(.*[^ ])' ]] && head=$match[1] || head=
  local prompt="#!/bin/zsh
# Shell history in $PWD
$(fc -ln -15 2>/dev/null)
$head"
  local out
  out=$(curl -s -m 0.8 "http://127.0.0.1:${HYPER_LLM_PORT:-8765}/v1/completions" \
    -H 'content-type: application/json' \
    -d "$(jq -nc --arg p "$prompt" '{prompt:$p,max_tokens:24,temperature:0,repetition_penalty:1.1,stop:["\n"]}')" \
    | jq -r '.choices[0].text // empty' 2>/dev/null) || return
  local full="${head:+$head }${out# }"
  full=${full//[[:cntrl:]]/}
  full=${full%% \#*}  # модель любит дописывать комментарий
  full=${full%%[[:space:]]}
  [[ $full == "$buf"?* ]] && typeset -g suggestion=$full
}

ZSH_AUTOSUGGEST_USE_ASYNC=1
(( ${ZSH_AUTOSUGGEST_STRATEGY[(I)llm]} )) || ZSH_AUTOSUGGEST_STRATEGY=(${ZSH_AUTOSUGGEST_STRATEGY:-history} llm)
