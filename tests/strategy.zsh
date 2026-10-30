#!/usr/bin/env zsh
# Тест zsh-стратегии против стаб-сервера: склейка, фильтры, мёртвый API.
emulate -L zsh
cd "${0:A:h}/.."
export HYPER_LLM_PORT=18765
source zsh/llm-complete.zsh
fc() { print 'git status' }

fail=0
check() {  # check <буфер> <ответ модели> <ожидаемая подсказка>
  print -r -- "$2" > "$TMPDIR/stub-reply"
  suggestion=
  _zsh_autosuggest_strategy_llm "$1"
  [[ $suggestion == "$3" ]] && print "ok   [$1] -> [$3]" || { print "FAIL [$1] -> [$suggestion], ждали [$3]"; fail=1 }
}

suggestion=
_zsh_autosuggest_strategy_llm 'git pu'
[[ -z $suggestion ]] && print 'ok   мёртвый API -> пусто' || { print 'FAIL мёртвый API'; fail=1 }

python3 -I -c '
import http.server, json, sys, os
f = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers["content-length"]))
        body = json.dumps({"choices": [{"text": open(f).read().rstrip("\n")}]}).encode()
        self.send_response(200); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", 18765), H).serve_forever()
' "$TMPDIR/stub-reply" &
stub=$!
trap "kill $stub" EXIT
sleep 0.5

check 'git pu'       'push origin main'       'git push origin main'
check 'git '         ' push # отправить'      'git push'
check 'git pu'       'status'                 ''
check 'ls '          $'-la\e[31m'            'ls -la[31m'
check 'docker comp'  'compose up -d'          'docker compose up -d'
check 'x'            'anything'               ''
exit $fail
