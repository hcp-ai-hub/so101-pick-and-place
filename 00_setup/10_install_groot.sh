#!/usr/bin/env bash
# ============================================================
# 10_install_groot.sh : NVIDIA GR00T N1.7 を LeRobot 経由で使うための追加インストール
# 参考: https://huggingface.co/blog/nvidia/nvidia-isaac-teleop-and-gr00t17-in-lerobot
#
# ★ 事前に ./00_install.sh を実行し、.venv を作成しておいてください。
# ★ GR00T N1.7 は3Bパラメータの大きめのVLAモデルです。学習には十分なGPU
#   （公式ブログではRTX 6000 Pro級で検証）を推奨します。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f "../.venv/bin/activate" ]; then
    echo "先に ./00_install.sh を実行して .venv を作成してください" >&2
    exit 1
fi
source "../.venv/bin/activate"

echo "== GR00T N1.7 用の追加パッケージをインストールします =="
# groot     : GR00T ポリシー本体 (lerobot-train/-rollout の --policy.type=groot)
# training  : lerobot-train (00_install.sh で導入済みだが組み合わせのため再指定)
# feetech   : SO-101 のモーター制御 (同上)
# viz       : lerobot-record 等でのデータ可視化
uv pip install --python ../.venv 'lerobot[groot,training,feetech,viz]'

echo ""
echo "== インストール完了 =="
echo "動作確認: lerobot-train --help  (--policy.type の選択肢に groot が出るか確認)"
echo ""
echo "もし --policy.type=groot が使えない場合（PyPI版がまだ追随していない場合）は、"
echo "LeRobot を GitHub 最新版から入れ直してください:"
echo '  uv pip install --python ../.venv "lerobot[groot,training,feetech,viz] @ git+https://github.com/huggingface/lerobot.git"'
