#!/usr/bin/env bash
# ============================================================
# 02_setup_motors_leader.sh : リーダーアームの各モーターの ID / ボーレート設定
# 事前に config.common.env の LEADER_PORT を設定してください
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

# uv で作成した仮想環境 (.venv) があれば自動で有効化
if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi
source ../config.common.env

# --- 既に設定済みでないか事前チェック（うっかり再実行での事故防止） ---
echo "モーターが既に設定済みでないか確認しています..."
if python tools/check_motors_configured.py --type=leader --port="$LEADER_PORT"; then
    echo ""
    echo "!! 警告 !!: 6個全てのモーターが既に期待通りのIDで応答しました。"
    echo "既に motor ID 設定が完了している可能性が高いです。"
    echo "このままもう一度実行すると、正常なモーターのIDも上書き・破壊するおそれがあります。"
    echo ""
    echo "特定の1個だけ直したい場合は、このスクリプトではなく ./tools/fix_motor_id.sh を使ってください。"
    echo "  例: ./tools/fix_motor_id.sh leader gripper"
    echo ""
    read -p "それでも6個全部を最初からやり直しますか？ (yes と入力してEnter、他は中止): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "中止しました。"
        exit 1
    fi
fi


echo "リーダーアームのモーターを1つずつ設定します。"
echo "画面の指示に従い、指定されたモーターだけをボードに接続した状態でEnterを押してください。"
echo "設定順: gripper -> wrist_roll -> wrist_flex -> elbow_flex -> shoulder_lift -> shoulder_pan"
echo ""

lerobot-setup-motors \
    --teleop.type=so101_leader \
    --teleop.port="${LEADER_PORT}"
