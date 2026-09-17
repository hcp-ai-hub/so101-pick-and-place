#!/usr/bin/env bash
# ============================================================
# 01_setup_client.sh : SO-100/SO-101実機クライアント側の依存関係をセットアップ
# 参考: https://github.com/NVIDIA/Isaac-GR00T/blob/main/examples/SO100/README.md
#
# ★ 事前に ./00_setup_isaac_groot.sh を実行し、test/Isaac-GR00T を用意しておいてください。
# ★ venvは既にactivate済みの前提で実行します（このスクリプトではvenvの作成・
#   activateは行いません）。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d "Isaac-GR00T" ]; then
    echo "先に ./00_setup_isaac_groot.sh を実行してください" >&2
    exit 1
fi

cd Isaac-GR00T/gr00t/eval/real_robot/SO100

echo "== クライアント側の依存関係をインストールします (activate済みのvenvを使用) =="
uv pip install -e . --verbose
# リポジトリ本体 (gr00t パッケージ・Policy API) を依存関係なしで追加インストール
uv pip install --no-deps -e ../../../../

echo ""
echo "== セットアップ完了 =="
echo "次は ./02_start_groot_server.sh を（別ターミナルで）実行してください。"
