#!/bin/sh
# The example plugin of earshot (docs/PLUGINS.md). It answers each command with the number of its words.
# It reads one JSON line for each message from stdin, and writes one JSON line for each answer to stdout.
# It stops when stdin closes.
while IFS= read -r line; do
  case "$line" in
    *'"type":"command"'*)
      id=$(printf '%s' "$line" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
      text=$(printf '%s' "$line" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p')
      count=$(printf '%s' "$text" | wc -w | tr -d ' ')
      printf '{"type":"answer","re":"%s","kind":"note","text":"%s words"}\n' "$id" "$count"
      ;;
  esac
done
