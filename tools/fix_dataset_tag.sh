#!/usr/bin/env bash
# ============================================================
# fix_dataset_tag.sh : Hub上のデータセットに codebase_version tag を
#                       付け直す（fix_dataset_tag.py のラッパー）
#
# こんなときに使ってください:
#   lerobot-train / lerobot-rollout 実行時に
#     "RevisionNotFoundError: Your dataset must be tagged with a
#      codebase version."
#   というエラーが出た場合。多くは 01_collect/06_record_dataset.sh 内の
#   lerobot-record によるアップロードが失敗し、スクリプトが案内する
#   手動コマンド `hf upload <repo_id> <dir> --repo-type dataset` で
#   やり直した後に起きます（hf upload はファイルを置くだけで、
#   push_to_hub() が自動でやるバージョンtag付けをしないため）。
#
# 使い方:
#   ./tools/fix_dataset_tag.sh                       # config.common.env の DATASET_REPO_ID に対して実行
#   ./tools/fix_dataset_tag.sh other/repo_id         # 別のrepo_idを指定
#   ./tools/fix_dataset_tag.sh other/repo_id v3.0    # tagのバージョンも明示指定
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi
source ../config.common.env

REPO_ID="${1:-${DATASET_REPO_ID}}"
VERSION="${2:-}"

if [ -n "$VERSION" ]; then
    python fix_dataset_tag.py --repo-id="$REPO_ID" --version="$VERSION"
else
    python fix_dataset_tag.py --repo-id="$REPO_ID"
fi
