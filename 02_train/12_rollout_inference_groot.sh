#!/usr/bin/env bash
# ============================================================
# 12_rollout_inference_groot.sh : 学習済み GR00T N1.7 ポリシーで自律動作させる（推論）
# 使い方:
#   ./02_train/12_rollout_inference_groot.sh                       # Hub上の GROOT_REPO_ID を使う
#   ./02_train/12_rollout_inference_groot.sh 60 ./outputs/train/.../pretrained_model  # ローカルckptを使う
#   第1引数: 動作時間(秒, 省略時60) / 第2引数: policy.path を上書き(省略時 GROOT_REPO_ID)
#
# 参考: https://huggingface.co/blog/nvidia/nvidia-isaac-teleop-and-gr00t17-in-lerobot
#
# ★ 重要: ロボットの開始姿勢（レストポーズ）とカメラの位置は、収録時
#   (01_collect/06_record_dataset.sh) と必ず揃えてください。ズレているとカメラが
#   作業台を十分に写せず、タスクを認識できないことがあります。
#   詳しくは docs/CAMERA_SETUP.md を参照してください。
#
# ★ 重要: 11_train_policy_groot.sh は --policy.use_relative_actions=true で
#   学習するため、通常の(1ステップずつselect_actionを呼ぶ)推論パスは
#   "GrootPolicy.select_action does not support relative-action policies"
#   というNotImplementedErrorになります。これを避けるため、下のlerobot-rolloutでは
#   公式ドキュメント(huggingface/lerobot docs/source/groot.mdx)の推奨どおり
#   --inference.type=rtc (RTC/チャンク推論パス) を指定しています。
#   11番の学習を use_relative_actions=false に変更した場合は、このRTC指定は
#   無くても動くはずですが、付けたままでも問題ありません。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi
source ../config.common.env
source ../config.train.env

DURATION="${1:-60}"
POLICY_PATH="${2:-${GROOT_REPO_ID}}"

lerobot-rollout \
    --strategy.type=base \
    --policy.path="${POLICY_PATH}" \
    --policy.base_model_path="${GROOT_BASE_MODEL_PATH}" \
    --policy.n_action_steps="${GROOT_ROLLOUT_N_ACTION_STEPS}" \
    --robot.type=so101_follower \
    --robot.port="${FOLLOWER_PORT}" \
    --robot.id="${FOLLOWER_ID}" \
    --robot.cameras="${CAMERA_CONFIG}" \
    --task="${TASK_DESCRIPTION}" \
    --duration="${DURATION}" \
    --display_data="${DISPLAY_DATA}" \
    --inference.type=rtc \
    --inference.rtc.enabled=true \
    --inference.rtc.execution_horizon="${GROOT_ROLLOUT_N_ACTION_STEPS}" \
    --inference.queue_threshold=0
