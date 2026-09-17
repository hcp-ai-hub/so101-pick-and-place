#!/usr/bin/env bash
# ============================================================
# 00_setup_isaac_groot.sh : NVIDIA公式 Isaac-GR00T リポジトリを clone してセットアップ
# 参考: https://github.com/NVIDIA/Isaac-GR00T (README) / examples/SO100/README.md
#
# ★ so101-aist 本体 (../.venv) とは完全に別の環境です。ここで作る .venv は
#   test/Isaac-GR00T の中だけで使います。
# ★ GPUメモリ 16GB以上 (推論のみの場合) が必要です。Python 3.12 / CUDA対応GPU前提。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v uv >/dev/null 2>&1; then
    echo "uv が見つからないのでインストールします..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

# ★ git-lfs は不要です（2026-09-16確認）。このリポジトリで filter=lfs が
#   付いているのは .gitattributes 上で media/*.gif, demo_data/**/*.mp4,
#   demo_data/**/*.parquet, examples内の一部動画, scripts/deployment/
#   {dgpu,spark,jetson}/wheels/*.whl だけで、このtestトラックが使う
#   gr00t/eval/real_robot/SO100/eval_so100.py 等のソースコードには無関係です。
#   GIT_LFS_SKIP_SMUDGE=1 を付けておくと、万一 git-lfs がインストール済みの
#   環境でも上記LFS対象ファイルの実体をダウンロードせずポインタのテキストの
#   ままにしてくれます（容量・時間の節約）。後で実体が必要になったら
#   `cd Isaac-GR00T && git lfs pull --include=<path>` してください
#   （その場合は git-lfs のインストールが別途必要です）。
if [ ! -d "Isaac-GR00T" ]; then
    echo "== Isaac-GR00T を clone します (サブモジュール込み, git-lfsは未使用) =="
    GIT_LFS_SKIP_SMUDGE=1 git clone --recurse-submodules https://github.com/NVIDIA/Isaac-GR00T
else
    echo "Isaac-GR00T は既に存在するのでcloneはスキップします（更新したい場合は 'cd Isaac-GR00T && git pull' してください）"
fi

cd Isaac-GR00T

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "== ffmpeg をインストールします (apt) =="
    sudo apt-get update && sudo apt-get install -y ffmpeg
fi

echo "== uv sync で依存関係をインストールします (Python 3.12) =="
uv sync --python 3.12

echo ""
echo "== 動作確認 =="
uv run python -c "import gr00t; print('GR00T installed successfully')"

echo ""
echo "== インストール完了 =="
echo "GR00T-N1.7-3B はHugging Face上のgatedモデルです。事前にログインしてください:"
echo "  uv run huggingface-cli login"
echo "または環境変数で:"
echo "  export HF_TOKEN=<あなたのトークン>"
echo ""
echo "次は ./01_setup_client.sh を実行してください。"
