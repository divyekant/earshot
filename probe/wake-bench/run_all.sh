#!/bin/bash
# Runs every step of the bench in order. Put the data in place first (see README.md).
# Each step skips the work that is done, so you can stop the script and start it again.
set -euo pipefail
cd "$(dirname "$0")"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
VOICES="libritts12 libritts140 libritts377 libritts590 vctk2 vctk40 vctk77 arctic0 arctic5 arctic11"
DATA="${WAKE_DATA:-data}"

uv run python libri_frames.py 0 1
for i in 0 1 2 3 4 5 6 7 8 9; do
  uv run python gen.py "$i"
  uv run python gen_far.py "$i"
done
mkdir -p "$DATA/results"
for v in $VOICES; do
  [ -f "$DATA/results/$v.pkl" ] || NOCROSS=1 uv run python eval_voice.py "$v" 0.75
done
uv run python cross.py
uv run python eval_far.py
uv run python analyse.py
uv run python analyse.py sweep
uv run python analyse.py far
