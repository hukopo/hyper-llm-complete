#!/bin/sh
# Сторож: guard.sh <pid родителя> <команда...>
# Гасит команду, когда родитель умер (даже по kill -9) или сам сторож получил TERM.
parent=$1; shift
"$@" & c=$!
trap 'kill $c 2>/dev/null' TERM INT
while kill -0 "$parent" 2>/dev/null && kill -0 $c 2>/dev/null; do sleep 1; done
kill $c 2>/dev/null; wait $c
