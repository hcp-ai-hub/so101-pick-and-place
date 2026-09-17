#!/usr/bin/env bash
# ============================================================
# 08_train_policy.sh : 収録したデータセットで方策 (policy) を学習する
# GPU/Apple Silicon がない場合は config.train.env の POLICY_DEVICE を cpu にしてください
#
# Weights & Biases でログを見るかどうかは config.train.env の WANDB_ENABLE で制御します
# （既定 true）。認証は config.train.env の WANDB_API_KEY を使います。
#
# チェックポイントの保存先は config.train.env の SAVE_CHECKPOINT_TO_HUB /
# CHECKPOINT_LOCAL_CLEANUP で制御します（既定: Hubに逐次アップロードし、
# アップロード確認済みのローカルコピーは自動削除 = 実質Hubのみに保存）。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

# uv で作成した仮想環境 (.venv) があれば自動で有効化
if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi
source ../config.common.env
source ../config.train.env

# POLICY_DEVICE=auto の場合、.venv の PyTorch が実際に CUDA を使えるかで判定します。
# CUDAが使えない場合は cpu に黙ってフォールバックせず、ここでエラー終了します
# （学習をCPUで走らせても実用的な時間で終わらないため、気付かないままCPU学習が
#   走り続けるより早期に失敗させる方針）。CPUで意図的に動かしたい場合のみ、
# config.train.env の POLICY_DEVICE を "auto" ではなく "cpu" に明示指定してください。
RESOLVED_DEVICE="${POLICY_DEVICE}"
if [ "${RESOLVED_DEVICE}" = "auto" ]; then
    if python -c "import torch, sys; sys.exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
        RESOLVED_DEVICE="cuda"
        echo "POLICY_DEVICE=auto -> 自動判定結果: ${RESOLVED_DEVICE}"
    else
        echo "エラー: .venv の PyTorch から CUDA が利用できません (torch.cuda.is_available() = False)。" >&2
        if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
            echo "        nvidia-smi はGPUを検出しているので、CPU専用ビルドのtorchが入っている、" >&2
            echo "        ドライバとCUDAランタイムのバージョン不整合、CUDA_VISIBLE_DEVICES の設定などが" >&2
            echo "        考えられます。詳細:" >&2
            python -c "import torch; print('  torch version         :', torch.__version__); print('  torch built for CUDA  :', torch.version.cuda); print('  CUDA_VISIBLE_DEVICES  :', __import__('os').environ.get('CUDA_VISIBLE_DEVICES', '(未設定)'))" >&2 || true
        else
            echo "        nvidia-smi 自体もGPUを検出していません。GPUが載ったマシンで実行しているか確認してください。" >&2
        fi
        echo "        CPUで意図的に学習したい場合は config.train.env の POLICY_DEVICE=cpu を明示指定してください。" >&2
        exit 1
    fi
fi

# SAVE_CHECKPOINT_TO_HUB=true かつ CHECKPOINT_LOCAL_CLEANUP=true のとき、
# checkpoint_hub_gc.py をバックグラウンドで起動し、Hubへのアップロードが
# 確認できたローカルのチェックポイントを学習と並行して削除する
# （= 実質「チェックポイントはHubにのみ保存」）。このスクリプト終了時に必ず停止する。
GC_PID=""
if [ "${SAVE_CHECKPOINT_TO_HUB:-false}" = "true" ] && [ "${CHECKPOINT_LOCAL_CLEANUP:-false}" = "true" ]; then
    python ../tools/checkpoint_hub_gc.py --output-dir="${OUTPUT_DIR}" --repo-id="${POLICY_REPO_ID}" \
        --interval="${CHECKPOINT_GC_INTERVAL:-60}" &
    GC_PID=$!
    trap '[ -n "${GC_PID}" ] && kill "${GC_PID}" 2>/dev/null || true' EXIT
fi

lerobot-train \
    --dataset.repo_id="${DATASET_REPO_ID}" \
    --policy.type="${POLICY_TYPE}" \
    --output_dir="${OUTPUT_DIR}" \
    --job_name="${JOB_NAME}" \
    --policy.device="${RESOLVED_DEVICE}" \
    --policy.repo_id="${POLICY_REPO_ID}" \
    --policy.private="${HF_PRIVATE}" \
    --save_checkpoint_to_hub="${SAVE_CHECKPOINT_TO_HUB:-false}" \
    --wandb.enable="${WANDB_ENABLE:-false}"

# バックグラウンドのgcループを止めてから、最後に1回だけ仕上げのクリーンアップを実行
# （学習終了直前に保存された最後のチェックポイントを取りこぼさないため）
if [ -n "${GC_PID}" ]; then
    kill "${GC_PID}" 2>/dev/null || true
    wait "${GC_PID}" 2>/dev/null || true
    python ../tools/checkpoint_hub_gc.py --output-dir="${OUTPUT_DIR}" --repo-id="${POLICY_REPO_ID}" --once
fi

echo ""
echo "学習チェックポイントの保存先: ${OUTPUT_DIR}/checkpoints"
if [ "${SAVE_CHECKPOINT_TO_HUB:-false}" = "true" ] && [ "${CHECKPOINT_LOCAL_CLEANUP:-false}" = "true" ]; then
    echo "（CHECKPOINT_LOCAL_CLEANUP=true のため、Hubへのアップロードが確認できたローカルの"
    echo "  チェックポイントは自動削除済みです。実質的にHub上の ${POLICY_REPO_ID} のみに残ります。）"
    echo "途中から再開する場合（Hubから）:"
    echo "  lerobot-train --config_path=${POLICY_REPO_ID} --resume=true"
else
    echo "途中から再開する場合:"
    echo "  lerobot-train --config_path=${OUTPUT_DIR}/checkpoints/last/pretrained_model/train_config.json --resume=true"
fi
