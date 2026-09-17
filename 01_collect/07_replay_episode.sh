#!/usr/bin/env bash
# ============================================================
# 07_replay_episode.sh : 収録したエピソードをフォロワーアームに再生させる
# 使い方: ./01_collect/07_replay_episode.sh [エピソード番号(省略時は0)]
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

# uv で作成した仮想環境 (.venv) があれば自動で有効化
if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi
source ../config.common.env

EPISODE_INDEX="${1:-0}"

lerobot-replay \
    --robot.type=so101_follower \
    --robot.port="${FOLLOWER_PORT}" \
    --robot.id="${FOLLOWER_ID}" \
    --dataset.repo_id="${DATASET_REPO_ID}" \
    --dataset.episode="${EPISODE_INDEX}"
