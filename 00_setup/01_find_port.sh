#!/usr/bin/env bash
# ============================================================
# 01_find_port.sh : フォロワー / リーダーアームの USB ポート名を調べる
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

# uv で作成した仮想環境 (.venv) があれば自動で有効化
if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi

echo "手順:"
echo "  1) フォロワーアームだけ（またはリーダーアームだけ）USBケーブルを1本接続してこのスクリプトを実行"
echo "  2) 表示された指示に従い、いったんケーブルを抜いてEnterキーを押す"
echo "  3) 表示されたポート名を config.common.env の FOLLOWER_PORT / LEADER_PORT に書き写す"
echo "  4) もう片方のアームについても同じ手順を繰り返す"
echo ""

lerobot-find-port
