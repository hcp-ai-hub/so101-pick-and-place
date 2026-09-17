#!/usr/bin/env bash
# ============================================================
# checkpoint_hub_gc.sh : Hubへのアップロードが確認できたローカルの
#                         チェックポイントを削除する（checkpoint_hub_gc.pyのラッパー）
#
# 通常は 02_train/08_train_policy.sh / 02_train/11_train_policy_groot.sh が学習と並行して
# バックグラウンドで自動起動するため、手動で使うのは主に以下のような場合です:
#   - 学習を中断した後、確認済みのローカルチェックポイントだけ手動でまとめて掃除したい
#   - CHECKPOINT_LOCAL_CLEANUP=false で学習した後、後からまとめて掃除したい
#
# 使い方:
#   ./tools/checkpoint_hub_gc.sh                # config.train.env の POLICY_REPO_ID / OUTPUT_DIR に対して1回実行
#   ./tools/checkpoint_hub_gc.sh groot          # config.train.env の GROOT_REPO_ID / GROOT_OUTPUT_DIR に対して1回実行
#   ./tools/checkpoint_hub_gc.sh <repo_id> <output_dir>   # 任意のrepo_id/output_dirを指定
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi
source ../config.train.env

if [ "${1:-}" = "groot" ]; then
    REPO_ID="${GROOT_REPO_ID}"
    OUT_DIR="${GROOT_OUTPUT_DIR}"
elif [ -n "${1:-}" ]; then
    REPO_ID="$1"
    OUT_DIR="${2:-${OUTPUT_DIR}}"
else
    REPO_ID="${POLICY_REPO_ID}"
    OUT_DIR="${OUTPUT_DIR}"
fi

python checkpoint_hub_gc.py --output-dir="${OUT_DIR}" --repo-id="${REPO_ID}" --once
