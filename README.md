# hyper-llm-complete

Автодополнение команд zsh локальной LLM для [Hyper](https://hyper.is). Ответ приходит за 50–150 мс, работает офлайн на Apple Silicon.

- **HyperLLM.app** живёт в меню-баре и держит `mlx_lm.server` на `127.0.0.1:8765`. В меню: пауза (модель выгружается из RAM), выбор и скачивание модели, автозапуск при входе, лог.
- **Hyper-плагин** рисует точку в углу терминала (🟢 API есть, серая нет), запускает HyperLLM и подключает zsh-стратегию.
- **zsh-стратегия** для [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions): сначала история, потом LLM. Если API не отвечает, подсказки идут только из истории, и всё продолжает работать.

## Модели

| Модель | Размер | |
|---|---|---|
| Qwen2.5 Coder 0.5B (base) | 290 МБ | по умолчанию, быстрая |
| Qwen2.5 Coder 1.5B (base) | 880 МБ | точнее |
| Qwen3.5 2B | 1.6 ГБ | берётся из кэша [QwenWhisper](https://github.com/hukopo/qwenwishper), если он есть |

Модели скачиваются при выборе в меню и хранятся в кэше Hugging Face (`~/.cache/huggingface`).

## Установка

Нужны Apple Silicon, macOS 13+, `uv`, `jq` и oh-my-zsh.

```bash
git clone https://github.com/hukopo/hyper-llm-complete ~/projects/hyper-llm-complete
~/projects/hyper-llm-complete/scripts/install.sh
```

Скрипт ставит `mlx-lm` и `zsh-autosuggestions`, собирает `~/Applications/HyperLLM.app` и линкует плагин. Дальше:

1. `~/.hyper.js`: `localPlugins: ["hyper-llm-complete"]`
2. `~/.zshrc`: добавить `zsh-autosuggestions` в `plugins=(...)`, а после строки с `oh-my-zsh.sh`:
   ```zsh
   [[ -n $HYPER_LLM_ZSH ]] && source $HYPER_LLM_ZSH
   ```
3. Перезапустить Hyper. Подсказка принимается клавишей `→`.

## Процессы

Сервер запускается через sh-сторожа. Сторож завершает его, если HyperLLM закрылся любым способом, включая `kill -9`. Поэтому сирот не остаётся.

## Тесты

```bash
npm test
```
