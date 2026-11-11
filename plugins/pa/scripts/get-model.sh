#!/bin/sh
# Downloads one embedding model file of the PA plugin (phase 2, E10) at a fixed revision, and checks its SHA-256 sum.
# The PA program has no network code: this script is the only download.
# Usage: scripts/get-model.sh qwen3|gemma <folder>
set -eu

name="${1:?name: qwen3 or gemma}"
folder="${2:?folder}"

case "$name" in
  qwen3)
    repo="Qwen/Qwen3-Embedding-0.6B-GGUF"
    revision="370f27d7550e0def9b39c1f16d3fbaa13aa67728"
    file="Qwen3-Embedding-0.6B-Q8_0.gguf"
    sha="06507c7b42688469c4e7298b0a1e16deff06caf291cf0a5b278c308249c3e439"
    ;;
  gemma)
    repo="ggml-org/embeddinggemma-300M-GGUF"
    revision="0f741b5a6585bd53aeb15cd1372c56f2a0f65e12"
    file="embeddinggemma-300M-Q8_0.gguf"
    sha="b5ce9d77a3fc4b3b39ccb5643c36777911cc4eb46a66962eadfa3f5f60490d63"
    ;;
  *)
    echo "Unknown model: $name" >&2
    exit 2
    ;;
esac

mkdir -p "$folder"
target="$folder/$file"
check() { [ "$(shasum -a 256 "$1" | cut -d ' ' -f 1)" = "$sha" ]; }

if [ -f "$target" ] && check "$target"; then
  echo "$target"
  exit 0
fi

part="$target.part"
curl -fL --retry 3 -o "$part" "https://huggingface.co/$repo/resolve/$revision/$file"
if ! check "$part"; then
  echo "The SHA-256 sum of $file is not correct. The file is not kept." >&2
  rm -f "$part"
  exit 1
fi
mv "$part" "$target"
echo "$target"
