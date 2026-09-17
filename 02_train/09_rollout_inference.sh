#!/usr/bin/env bash
# ============================================================
# 09_rollout_inference.sh : 学習済みポリシーで自律動作させる（推論）
# 使い方: ./02_train/09_rollout_inference.sh [動作時間(秒), 省略時は60]
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

# uv で作成した仮想環境 (.venv) があれば自動で有効化
if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi
source ../config.common.env
source ../config.train.env

DURATION="${1:-60}"

lerobot-rollout \
    --strategy.type=base \
    --policy.path="${POLICY_REPO_ID}" \
    --robot.type=so101_follower \
    --robot.port="${FOLLOWER_PORT}" \
    --robot.id="${FOLLOWER_ID}" \
    --robot.cameras="${CAMERA_CONFIG}" \
    --task="${TASK_DESCRIPTION}" \
    --duration="${DURATION}"
