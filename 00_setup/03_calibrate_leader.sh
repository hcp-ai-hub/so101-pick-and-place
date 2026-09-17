#!/usr/bin/env bash
# ============================================================
# 03_calibrate_leader.sh : リーダーアームのキャリブレーション
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

# uv で作成した仮想環境 (.venv) があれば自動で有効化
if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi
source ../config.common.env

echo "リーダーアームのキャリブレーションを行います。"
echo "  1) 全ての関節を可動域のだいたい中央に動かしてEnterを押す"
echo "  2) その後、各関節をゆっくり可動域いっぱいまで動かす（指示に従う）"
echo ""

lerobot-calibrate \
    --teleop.type=so101_leader \
    --teleop.port="${LEADER_PORT}" \
    --teleop.id="${LEADER_ID}"
