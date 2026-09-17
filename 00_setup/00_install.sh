#!/usr/bin/env bash
# ============================================================
# 00_install.sh : uv を使った LeRobot のインストール（SO-101 / Feetechモーター対応）
# 参考:
#   https://huggingface.co/docs/lerobot/so101
#   https://huggingface.co/docs/lerobot/installation
#
# ★ このスクリプトはロボットが接続されている実機の Terminal で実行してください。
#   リモートシェルやコンテナ・VM経由ではUSBシリアルポートにアクセスできません。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

# --- uv 自体が入っていなければインストール -------------------------
if ! command -v uv >/dev/null 2>&1; then
  echo "uv が見つからないのでインストールします..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
echo "uv バージョン: $(uv --version)"

# --- 仮想環境の作成 -------------------------------------------------
# LeRobot は Python >= 3.12 が必要です。3.12 がPCに無くても uv が自動でダウンロード
# してくれるので、事前に pyenv 等でPythonを用意する必要はありません。
echo "== .venv を作成します (Python 3.12) =="
uv venv --python 3.12 ../.venv

echo "== LeRobot をインストールします =="
# feetech       : SO-101 の Feetech(STS3215) モーター対応
# core_scripts  : lerobot-find-port / lerobot-calibrate / lerobot-teleoperate /
#                 lerobot-record / lerobot-replay など実機操作系CLI
# training      : lerobot-train など学習系
uv pip install --python ../.venv 'lerobot[feetech,core_scripts,training]'

# --- ffmpeg ----------------------------------------------------------
# 動画デコードに TorchCodec が使われるため ffmpeg が必要です（Mac/Linux共通）。
if ! command -v ffmpeg >/dev/null 2>&1; then
  OS_NAME="$(uname -s)"
  if [ "$OS_NAME" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    echo "== ffmpeg をインストールします (Homebrew) =="
    brew install ffmpeg
  elif [ "$OS_NAME" = "Linux" ] && command -v apt-get >/dev/null 2>&1; then
    echo "== ffmpeg をインストールします (apt) =="
    sudo apt-get update && sudo apt-get install -y ffmpeg
  elif [ "$OS_NAME" = "Linux" ] && command -v dnf >/dev/null 2>&1; then
    echo "== ffmpeg をインストールします (dnf) =="
    sudo dnf install -y ffmpeg
  elif [ "$OS_NAME" = "Linux" ] && command -v pacman >/dev/null 2>&1; then
    echo "== ffmpeg をインストールします (pacman) =="
    sudo pacman -S --noconfirm ffmpeg
  else
    cat <<'NOTE'

ffmpeg が見つかりません。お使いの環境に合わせて導入してください:
  - Mac (Homebrew未導入): https://brew.sh/ の手順で導入後 `brew install ffmpeg`
  - Linux (上記以外のパッケージマネージャ): 各ディストリの手順で `ffmpeg` をインストール

NOTE
  fi
fi

echo ""
echo "== インストール完了 =="
echo "以降のスクリプト (01_*.sh 以降) は仮想環境 .venv を自動で有効化して実行します。"
echo "自分で直接コマンドを打ちたい場合は、まず以下で有効化してください:"
echo "  source \"$(cd .. && pwd)/.venv/bin/activate\""
echo "動作確認: lerobot-find-port --help"
