#!/usr/bin/env bash
# ============================================================
# 02_start_groot_server.sh : GR00Tポリシーサーバーを起動する（素の nvidia/GR00T-N1.7-3B を使用）
# 参考: https://github.com/NVIDIA/Isaac-GR00T/blob/main/examples/SO100/README.md
#
# ★ このスクリプトは起動したままにしておく必要があります。
#   03_run_pretrained_rollout.sh は「別のターミナル」から実行してください。
# ★ ファインチューニング無しの nvidia/GR00T-N1.7-3B をそのまま読み込みます
#   （NEW_EMBODIMENT用の行動出力部分は未学習です。test/README.md の「期待値」参照）。
# ★ GPU VRAM 16GB以上が必要です。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/Isaac-GR00T"

MODEL_PATH="${1:-nvidia/GR00T-N1.7-3B}"

echo "GR00Tポリシーサーバーを起動します (model-path=${MODEL_PATH})"
echo "起動完了のログが出たら、別ターミナルで ./03_run_pretrained_rollout.sh を実行してください。"
echo "止めるときは Ctrl+C です。"
echo ""

python gr00t/eval/run_gr00t_server.py \
    --model-path "${MODEL_PATH}" \
    --embodiment-tag NEW_EMBODIMENT
