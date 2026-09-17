#!/usr/bin/env bash
# ============================================================
# 13_train_policy_groot_multi_gpu.sh : GR00T N1.7 (NVIDIA) を複数GPUでファインチューニング
# 事前に ./00_setup/10_install_groot.sh を実行してください
#
# 11_train_policy_groot.sh の内容はそのままに、LeRobot公式のマルチGPU学習機構
# （Hugging Face `accelerate`）で起動する版です。単体GPUで学習する場合は
# 11_train_policy_groot.sh を使ってください（このスクリプトは複数GPU専用で、
# GPUが1枚しか検出できない場合はエラーで停止します）。
#
# 参考: https://huggingface.co/docs/lerobot/multi_gpu_training
#       https://huggingface.co/blog/nvidia/nvidia-isaac-teleop-and-gr00t17-in-lerobot
#
# ★ 学習内容（データセット・ポリシー設定など）は 11_train_policy_groot.sh と同じ
#   config.train.env の GROOT_* 変数を使います。このスクリプト独自の追加設定は
#   GROOT_NUM_GPUS / GROOT_MULTI_GPU_MIXED_PRECISION の2つだけです。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi
source ../config.common.env
source ../config.train.env

# デフォルトでは Hugging Face Hub にアクセスできる状態（オンライン）で学習します。
# （11_train_policy_groot.sh と同じロジック）
export HF_HUB_OFFLINE="${HF_HUB_OFFLINE:-0}"
if [ "${HF_HUB_OFFLINE}" = "1" ]; then
    echo "HF_HUB_OFFLINE=1 -> Hugging Face Hub にはアクセスせず、ローカルキャッシュのみで学習します。"

    GROOT_BASE_MODEL_CACHE_DIR="${HOME}/.cache/huggingface/hub/models--${GROOT_BASE_MODEL_PATH//\//--}"
    if ! find "${GROOT_BASE_MODEL_CACHE_DIR}" -name "*.safetensors*" 2>/dev/null | grep -q .; then
        cat <<MSG >&2
エラー: ベースモデル ${GROOT_BASE_MODEL_PATH} の重みファイル(.safetensors)が
ローカルにキャッシュされていません（${GROOT_BASE_MODEL_CACHE_DIR} が見つからない/空）。

このモデルは gated（要ログイン・要利用規約への同意）なため、オフラインモードのままでは
自動ダウンロードできません。最初の1回だけ、以下を行ってからもう一度実行してください。

  1. https://huggingface.co/${GROOT_BASE_MODEL_PATH} を開いて利用規約に同意する
  2. hf auth login --add-to-git-credential  # まだログインしていない場合
  3. HF_HUB_OFFLINE=0 ./02_train/13_train_policy_groot_multi_gpu.sh   # オンラインでベースモデルをDL

一度ダウンロードされてローカルにキャッシュされれば、以降は HF_HUB_OFFLINE=1 を指定した
オフライン学習も可能になります。
MSG
        exit 1
    fi
else
    echo "HF_HUB_OFFLINE=0 -> Hugging Face Hub にアクセスしながら学習します（デフォルト）。"
fi

# --- CUDA / GPU枚数のチェック --------------------------------------------
# このスクリプトは複数GPUでの学習が前提のため、POLICY_DEVICE=auto/cuda 以外
# （cpu など）は明示的にエラーにします。CPUで動かしたい場合は 11 番を使ってください。
if [ "${POLICY_DEVICE}" != "auto" ] && [ "${POLICY_DEVICE}" != "cuda" ]; then
    echo "エラー: 13_train_policy_groot_multi_gpu.sh は複数GPU学習専用のため、" >&2
    echo "        POLICY_DEVICE=${POLICY_DEVICE} には対応していません。" >&2
    echo "        config.train.env の POLICY_DEVICE を auto または cuda にしてください。" >&2
    exit 1
fi

if ! python -c "import torch, sys; sys.exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
    echo "エラー: .venv の PyTorch から CUDA が利用できません (torch.cuda.is_available() = False)。" >&2
    echo "        GR00T N1.7 の複数GPU学習にはCUDAが必須です。詳細:" >&2
    python -c "import torch; print('  torch version         :', torch.__version__); print('  torch built for CUDA  :', torch.version.cuda); print('  CUDA_VISIBLE_DEVICES  :', __import__('os').environ.get('CUDA_VISIBLE_DEVICES', '(未設定)'))" >&2 || true
    exit 1
fi

if ! command -v accelerate >/dev/null 2>&1; then
    echo "エラー: accelerate コマンドが見つかりません。" >&2
    echo "        通常は 00_setup/00_install.sh / 00_setup/10_install_groot.sh でインストールされる" >&2
    echo "        lerobot[training] の依存関係に含まれています。.venv を有効化した状態で" >&2
    echo "        'uv pip install accelerate' を試してください。" >&2
    exit 1
fi

# GROOT_NUM_GPUS が未設定/空なら nvidia-smi で検出できるGPU枚数を自動で使う。
# 使うGPUを絞りたい場合は config.train.env の GROOT_NUM_GPUS に明示的に枚数を指定するか、
# 実行時に CUDA_VISIBLE_DEVICES=0,1 のように渡して見えるGPU自体を絞ってください。
if [ -n "${GROOT_NUM_GPUS:-}" ]; then
    NUM_GPUS="${GROOT_NUM_GPUS}"
    echo "GROOT_NUM_GPUS が指定されているためGPU枚数として使用: ${NUM_GPUS}"
else
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        echo "エラー: nvidia-smi が見つからず、GPU枚数を自動検出できません。" >&2
        echo "        config.train.env の GROOT_NUM_GPUS に枚数を明示指定してください。" >&2
        exit 1
    fi
    NUM_GPUS="$(nvidia-smi -L | wc -l)"
    echo "GROOT_NUM_GPUS 未指定のため nvidia-smi から自動検出: ${NUM_GPUS} 枚"
fi

if [ "${NUM_GPUS}" -lt 2 ]; then
    echo "エラー: 検出/指定されたGPU枚数が ${NUM_GPUS} 枚のため、複数GPU学習になりません。" >&2
    echo "        1枚だけで学習する場合は 11_train_policy_groot.sh を使ってください。" >&2
    exit 1
fi

echo "=> accelerate launch --multi_gpu --num_processes=${NUM_GPUS} で学習します。"

# SAVE_CHECKPOINT_TO_HUB=true かつ CHECKPOINT_LOCAL_CLEANUP=true のとき、
# checkpoint_hub_gc.py をバックグラウンドで起動する（11_train_policy_groot.sh と同じ仕組み）。
GC_PID=""
if [ "${SAVE_CHECKPOINT_TO_HUB:-false}" = "true" ] && [ "${CHECKPOINT_LOCAL_CLEANUP:-false}" = "true" ]; then
    python ../tools/checkpoint_hub_gc.py --output-dir="${GROOT_OUTPUT_DIR}" --repo-id="${GROOT_REPO_ID}" \
        --interval="${CHECKPOINT_GC_INTERVAL:-60}" &
    GC_PID=$!
    trap '[ -n "${GC_PID}" ] && kill "${GC_PID}" 2>/dev/null || true' EXIT
fi

# --batch_size はプロセスごと（GPU 1枚あたり）のバッチサイズです。
# 実効バッチサイズは GROOT_BATCH_SIZE × NUM_GPUS になります（accelerateはbatch_sizeを
# 自動でスケーリングしません）。学習率・ステップ数もGPU枚数に応じて自動調整されないため、
# 必要であれば config.train.env の GROOT_BATCH_SIZE / GROOT_STEPS を手動で調整してください。
#
# --policy.use_bf16=true でGR00Tポリシー自体がbf16キャストを行うため、accelerate側の
# --mixed_precision はデフォルト "no"（二重にキャストしない）にしています。純粋にaccelerate側の
# 機構で混合精度を使いたい場合は config.train.env の GROOT_MULTI_GPU_MIXED_PRECISION を "bf16"/"fp16" に
# 変更してください。
accelerate launch \
    --multi_gpu \
    --num_processes="${NUM_GPUS}" \
    --mixed_precision="${GROOT_MULTI_GPU_MIXED_PRECISION:-no}" \
    "$(which lerobot-train)" \
    --dataset.repo_id="${DATASET_REPO_ID}" \
    --dataset.image_transforms.enable=true \
    --policy.type=groot \
    --policy.device=cuda \
    --policy.base_model_path="${GROOT_BASE_MODEL_PATH}" \
    --policy.embodiment_tag="${GROOT_EMBODIMENT_TAG}" \
    --policy.chunk_size="${GROOT_CHUNK_SIZE}" \
    --policy.n_action_steps="${GROOT_TRAIN_N_ACTION_STEPS}" \
    --policy.use_relative_actions=true \
    --policy.relative_exclude_joints="${GROOT_RELATIVE_EXCLUDE_JOINTS}" \
    --policy.use_bf16=true \
    --policy.repo_id="${GROOT_REPO_ID}" \
    --policy.private="${HF_PRIVATE}" \
    --seed=42 \
    --batch_size="${GROOT_BATCH_SIZE}" \
    --steps="${GROOT_STEPS}" \
    --save_checkpoint=true \
    --save_freq="${GROOT_SAVE_FREQ}" \
    --save_checkpoint_to_hub="${SAVE_CHECKPOINT_TO_HUB:-false}" \
    --use_policy_training_preset=true \
    --output_dir="${GROOT_OUTPUT_DIR}" \
    --job_name="${GROOT_JOB_NAME}" \
    --wandb.enable="${GROOT_WANDB_ENABLE}"

# バックグラウンドのgcループを止めてから、最後に1回だけ仕上げのクリーンアップを実行
if [ -n "${GC_PID}" ]; then
    kill "${GC_PID}" 2>/dev/null || true
    wait "${GC_PID}" 2>/dev/null || true
    python ../tools/checkpoint_hub_gc.py --output-dir="${GROOT_OUTPUT_DIR}" --repo-id="${GROOT_REPO_ID}" --once
fi

echo ""
echo "学習チェックポイントの保存先: ${GROOT_OUTPUT_DIR}/checkpoints"
echo "（accelerate のマルチプロセス実行でも、チェックポイント保存/wandbログはメインプロセスのみが行うため"
echo "  保存先パスや再開方法は 11_train_policy_groot.sh と同じです。）"
if [ "${SAVE_CHECKPOINT_TO_HUB:-false}" = "true" ] && [ "${CHECKPOINT_LOCAL_CLEANUP:-false}" = "true" ]; then
    echo "（CHECKPOINT_LOCAL_CLEANUP=true のため、Hubへのアップロードが確認できたローカルの"
    echo "  チェックポイントは自動削除済みです。実質的にHub上の ${GROOT_REPO_ID} のみに残ります。）"
    echo "12_rollout_inference_groot.sh の POLICY_PATH には、Hubのrepo_idか、まだローカルに"
    echo "  残っているチェックポイントがあれば ${GROOT_OUTPUT_DIR}/checkpoints/last/pretrained_model を指定してください。"
    echo "途中から再開する場合（Hubから、複数GPUのまま再開するにはこのスクリプトを再実行）:"
    echo "  lerobot-train --config_path=${GROOT_REPO_ID} --resume=true"
elif [ "${SAVE_CHECKPOINT_TO_HUB:-false}" = "true" ]; then
    echo "12_rollout_inference_groot.sh の POLICY_PATH には、ローカルパスとして"
    echo "  ${GROOT_OUTPUT_DIR}/checkpoints/last/pretrained_model"
    echo "を指定してください（Hub上の ${GROOT_REPO_ID} にも各チェックポイントがpushされています）。"
else
    echo "12_rollout_inference_groot.sh の POLICY_PATH には、ローカルパスとして"
    echo "  ${GROOT_OUTPUT_DIR}/checkpoints/last/pretrained_model"
    echo "を指定してください（デフォルトではHubにpushしていません）。"
fi
