#!/usr/bin/env bash
# ============================================================
# 05_teleoperate_with_camera.sh : カメラ映像を見ながらテレオペする
# カメラ設定は config.common.env の CAMERA_CONFIG を編集してください
# 参考: https://huggingface.co/docs/lerobot/cameras
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

# uv で作成した仮想環境 (.venv) があれば自動で有効化
if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi
source ../config.common.env

lerobot-teleoperate \
    --robot.type=so101_follower \
    --robot.port="${FOLLOWER_PORT}" \
    --robot.id="${FOLLOWER_ID}" \
    --robot.cameras="${CAMERA_CONFIG}" \
    --teleop.type=so101_leader \
    --teleop.port="${LEADER_PORT}" \
    --teleop.id="${LEADER_ID}" \
    --display_data="${DISPLAY_DATA}"
