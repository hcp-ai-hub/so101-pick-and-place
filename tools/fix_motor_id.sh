#!/usr/bin/env bash
# ============================================================
# fix_motor_id.sh : 特定モーター1個だけIDを設定し直す（fix_motor_id.py のラッパー）
# 使い方:
#   ./tools/fix_motor_id.sh follower gripper
#   ./tools/fix_motor_id.sh follower shoulder_pan
#   ./tools/fix_motor_id.sh leader gripper
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi
source ../config.common.env

TYPE="${1:?使い方: ./tools/fix_motor_id.sh <follower|leader> <motor名>}"
MOTOR="${2:?使い方: ./tools/fix_motor_id.sh <follower|leader> <motor名>}"

if [ "$TYPE" = "follower" ]; then
    PORT="$FOLLOWER_PORT"
elif [ "$TYPE" = "leader" ]; then
    PORT="$LEADER_PORT"
else
    echo "type は follower か leader のどちらかにしてください" >&2
    exit 1
fi

python fix_motor_id.py --type="$TYPE" --port="$PORT" --motor="$MOTOR"
