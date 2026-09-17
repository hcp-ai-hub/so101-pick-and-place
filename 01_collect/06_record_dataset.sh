#!/usr/bin/env bash
# ============================================================
# 06_record_dataset.sh : 操作データを収録し Hugging Face Hub にアップロード
# 事前に `hf auth login --add-to-git-credential` でログインしてください
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

# uv で作成した仮想環境 (.venv) があれば自動で有効化
if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi
source ../config.common.env
source ../config.collect.env

cat <<NOTE
収録中のキー操作:
  → または n : 現在のエピソードを早期終了して次へ
  ← または r : このエピソードをやり直す（再収録）
  ESC または q : 収録セッションを終了し、動画をエンコードしてアップロード

収録するエピソード数: ${NUM_EPISODES}
タスク説明          : ${TASK_DESCRIPTION}
アップロード先       : ${DATASET_REPO_ID}
NOTE
echo ""

lerobot-record \
    --robot.type=so101_follower \
    --robot.port="${FOLLOWER_PORT}" \
    --robot.id="${FOLLOWER_ID}" \
    --robot.cameras="${CAMERA_CONFIG}" \
    --teleop.type=so101_leader \
    --teleop.port="${LEADER_PORT}" \
    --teleop.id="${LEADER_ID}" \
    --display_data="${DISPLAY_DATA}" \
    --dataset.repo_id="${DATASET_REPO_ID}" \
    --dataset.private="${HF_PRIVATE}" \
    --dataset.num_episodes="${NUM_EPISODES}" \
    --dataset.single_task="${TASK_DESCRIPTION}" \
    --dataset.episode_time_s="${EPISODE_TIME_S}" \
    --dataset.reset_time_s="${RESET_TIME_S}"

echo ""
echo "収録データはローカルにも保存されています: ~/.cache/huggingface/lerobot/${DATASET_REPO_ID}"
echo "手動でアップロードし直す場合:"
echo "  hf upload ${DATASET_REPO_ID} ~/.cache/huggingface/lerobot/${DATASET_REPO_ID} --repo-type dataset --private"
echo "  (Publicにしたい場合は --private を外してください)"
echo "  ※ 上記の hf upload はファイルを置くだけで、lerobot-record が普段自動で行う"
echo "    codebase_version の git tag 付けはしません。手動アップロード後に"
echo "    lerobot-train/lerobot-rollout で"
echo "    'Your dataset must be tagged with a codebase version' エラーが出た場合は"
echo "    ./tools/fix_dataset_tag.sh を実行してtagを付け直してください。"
