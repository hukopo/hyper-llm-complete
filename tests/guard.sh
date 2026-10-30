#!/bin/sh
# Тест сторожа: дочерний процесс не переживает ни kill -9 родителя, ни TERM сторожу.
cd "$(dirname "$0")/.."
fail=0

child_of() { for i in 1 2 3 4 5 6 7 8 9 10; do c=$(pgrep -P "$1") && { echo "$c"; return; }; sleep 0.1; done; }
dead_within() { for i in $(seq 30); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.1; done; return 1; }
check() { if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fail=1; fi; }

sleep 60 2>/dev/null & parent=$!
sh app/guard.sh "$parent" sleep 60 & g=$!
c=$(child_of $g)
kill -9 "$parent"
name="kill -9 родителя -> дочерний убит"; check dead_within "$c"

sleep 60 2>/dev/null & parent=$!
sh app/guard.sh "$parent" sleep 60 & g=$!
c=$(child_of $g)
kill "$g"
name="TERM сторожу -> дочерний убит"; check dead_within "$c"
kill "$parent"

sh app/guard.sh $$ sh -c 'exit 3'; rc=$?
name="код выхода команды пробрасывается"; check [ $rc -eq 3 ]

exit $fail
