#!/usr/bin/env bash
# ============================================================
# 03_run_pretrained_rollout.sh : クライアント側からロボットを動かす
# 使い方: ./03_run_pretrained_rollout.sh ["やってほしいタスクの説明（英語推奨）"]
#
# ★ 事前に別ターミナルで ./02_start_groot_server.sh を起動しておいてください。
# ★ front + wrist の2カメラが必須です（../config.common.env の本線設定とは別に、
#   このテストだけの CAMERA_CONFIG_TEST をここで定義しています）。
#   wrist カメラを一時的に繋ぎ直してから実行してください。
# ★ 安全上の注意: ファインチューニング無しの出力で動くので、予測不能な動きをする
#   前提で、周囲に物・人が無い状態・すぐ電源を切れる状態で実行してください。
#   まずは短いタイムアウトで試すことを推奨します。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

# FOLLOWER_PORT / FOLLOWER_ID は本線の config.common.env をそのまま流用
source ../config.common.env

# このテスト専用: front + wrist の2カメラ構成 (so100_config.py が両方を要求するため)
# index_or_path はご自身の環境の lerobot-find-cameras opencv の結果に書き換えてください。
CAMERA_CONFIG_TEST="{ wrist: {type: opencv, index_or_path: 2, width: 640, height: 480, fps: 30}, front: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 30} }"

LANG_INSTRUCTION="${1:-${TASK_DESCRIPTION}}"

cd Isaac-GR00T/gr00t/eval/real_robot/SO100

uv run --no-sync python eval_so100.py \
    --robot.type=so101_follower \
    --robot.port="${FOLLOWER_PORT}" \
    --robot.id="${FOLLOWER_ID}" \
    --robot.cameras="${CAMERA_CONFIG_TEST}" \
    --policy-host=localhost \
    --policy-port=5555 \
    --lang-instruction="${LANG_INSTRUCTION}"
