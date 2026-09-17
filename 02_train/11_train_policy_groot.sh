#!/usr/bin/env bash
# ============================================================
# 11_train_policy_groot.sh : GR00T N1.7 (NVIDIA) を収録データでファインチューニング
# 事前に ./00_setup/10_install_groot.sh を実行してください
# 参考: https://huggingface.co/blog/nvidia/nvidia-isaac-teleop-and-gr00t17-in-lerobot
#
# 08_train_policy.sh (ACT / pi0系) とは別トラックのGR00T専用スクリプトです。
# データ収録自体は既存の 01_collect/06_record_dataset.sh（リーダーアームでのテレオペ収録）
# をそのまま使えます。GR00Tは収録手段を問わず LeRobot Dataset 形式であれば学習できるため、
# 公式ブログのVRコントローラ (isaacteleop) は必須ではありません。
#
# ★ GR00Tの学習には LeRobot Dataset v3.0 形式が必要です。00_setup/10_install_groot.sh 実行後の
#   最新LeRobotで新規収録したデータセットであれば通常v3.0形式になります。古いデータ
#   セットを流用する場合はバージョンをご確認ください。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi
source ../config.common.env
source ../config.train.env

# デフォルトでは Hugging Face Hub にアクセスできる状態（オンライン）で学習します。
# ベースモデルや収録データセットの最新版をHubから参照できるようにするためのものです。
# Hubにアクセスせずローカルキャッシュのみで学習したい場合は、実行時に
#   HF_HUB_OFFLINE=1 ./02_train/11_train_policy_groot.sh
# のように上書きしてください。
export HF_HUB_OFFLINE="${HF_HUB_OFFLINE:-0}"
if [ "${HF_HUB_OFFLINE}" = "1" ]; then
    echo "HF_HUB_OFFLINE=1 -> Hugging Face Hub にはアクセスせず、ローカルキャッシュのみで学習します。"

    # GR00Tのベースモデル (GROOT_BASE_MODEL_PATH, gatedモデル) の重みファイルが
    # まだローカルにキャッシュされていない場合、オフラインモードだとダウンロードできず
    # 「model.safetensorsが無い」のような分かりにくいエラーになるため、事前にチェックする。
    GROOT_BASE_MODEL_CACHE_DIR="${HOME}/.cache/huggingface/hub/models--${GROOT_BASE_MODEL_PATH//\//--}"
    if ! find "${GROOT_BASE_MODEL_CACHE_DIR}" -name "*.safetensors*" 2>/dev/null | grep -q .; then
        cat <<MSG >&2
エラー: ベースモデル ${GROOT_BASE_MODEL_PATH} の重みファイル(.safetensors)が
ローカルにキャッシュされていません（${GROOT_BASE_MODEL_CACHE_DIR} が見つからない/空）。

このモデルは gated（要ログイン・要利用規約への同意）なため、オフラインモードのままでは
自動ダウンロードできません。最初の1回だけ、以下を行ってからもう一度実行してください。

  1. https://huggingface.co/${GROOT_BASE_MODEL_PATH} を開いて利用規約に同意する
  2. hf auth login --add-to-git-credential  # まだログインしていない場合
  3. HF_HUB_OFFLINE=0 ./02_train/11_train_policy_groot.sh   # オンラインでベースモデルをDL（デフォルトのまま）

一度ダウンロードされてローカルにキャッシュされれば、以降は HF_HUB_OFFLINE=1 を指定した
オフライン学習も可能になります。
MSG
        exit 1
    fi
else
    echo "HF_HUB_OFFLINE=0 -> Hugging Face Hub にアクセスしながら学習します（デフォルト）。"
fi

# POLICY_DEVICE=auto の場合、.venv の PyTorch が実際に CUDA を使えるかで判定します。
# CUDAが使えない場合は cpu に黙ってフォールバックせず、ここでエラー終了します
# （GR00T N1.7はCPUでの学習が現実的でないため、気付かないままCPU学習が走り続ける
#   より早期に失敗させる方針）。CPUで意図的に動かしたい場合のみ、config.train.env の
# POLICY_DEVICE を "auto" ではなく "cpu" に明示指定してください。
RESOLVED_DEVICE="${POLICY_DEVICE}"
if [ "${RESOLVED_DEVICE}" = "auto" ]; then
    if python -c "import torch, sys; sys.exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
        RESOLVED_DEVICE="cuda"
        echo "POLICY_DEVICE=auto -> 自動判定結果: ${RESOLVED_DEVICE}"
    else
        echo "エラー: .venv の PyTorch から CUDA が利用できません (torch.cuda.is_available() = False)。" >&2
        echo "        GR00T N1.7 はCPUでの学習が現実的ではないため、続行せず終了します。" >&2
        if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
            echo "        nvidia-smi はGPUを検出しているので、CPU専用ビルドのtorchが入っている、" >&2
            echo "        ドライバとCUDAランタイムのバージョン不整合、CUDA_VISIBLE_DEVICES の設定などが" >&2
            echo "        考えられます。詳細:" >&2
            python -c "import torch; print('  torch version         :', torch.__version__); print('  torch built for CUDA  :', torch.version.cuda); print('  CUDA_VISIBLE_DEVICES  :', __import__('os').environ.get('CUDA_VISIBLE_DEVICES', '(未設定)'))" >&2 || true
        else
            echo "        nvidia-smi 自体もGPUを検出していません。GPUが載ったマシンで実行しているか確認してください。" >&2
        fi
        exit 1
    fi
fi

# SAVE_CHECKPOINT_TO_HUB=true かつ CHECKPOINT_LOCAL_CLEANUP=true のとき、
# checkpoint_hub_gc.py をバックグラウンドで起動し、Hubへのアップロードが
# 確認できたローカルのチェックポイントを学習と並行して削除する
# （= 実質「チェックポイントはHubにのみ保存」）。このスクリプト終了時に必ず停止する。
GC_PID=""
if [ "${SAVE_CHECKPOINT_TO_HUB:-false}" = "true" ] && [ "${CHECKPOINT_LOCAL_CLEANUP:-false}" = "true" ]; then
    python ../tools/checkpoint_hub_gc.py --output-dir="${GROOT_OUTPUT_DIR}" --repo-id="${GROOT_REPO_ID}" \
        --interval="${CHECKPOINT_GC_INTERVAL:-60}" &
    GC_PID=$!
    trap '[ -n "${GC_PID}" ] && kill "${GC_PID}" 2>/dev/null || true' EXIT
fi

lerobot-train \
    --dataset.repo_id="${DATASET_REPO_ID}" \
    --dataset.image_transforms.enable=true \
    --policy.type=groot \
    --policy.device="${RESOLVED_DEVICE}" \
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
# （学習終了直前に保存された最後のチェックポイントを取りこぼさないため）
if [ -n "${GC_PID}" ]; then
    kill "${GC_PID}" 2>/dev/null || true
    wait "${GC_PID}" 2>/dev/null || true
    python ../tools/checkpoint_hub_gc.py --output-dir="${GROOT_OUTPUT_DIR}" --repo-id="${GROOT_REPO_ID}" --once
fi

echo ""
echo "学習チェックポイントの保存先: ${GROOT_OUTPUT_DIR}/checkpoints"
if [ "${SAVE_CHECKPOINT_TO_HUB:-false}" = "true" ] && [ "${CHECKPOINT_LOCAL_CLEANUP:-false}" = "true" ]; then
    echo "（CHECKPOINT_LOCAL_CLEANUP=true のため、Hubへのアップロードが確認できたローカルの"
    echo "  チェックポイントは自動削除済みです。実質的にHub上の ${GROOT_REPO_ID} のみに残ります。）"
    echo "12_rollout_inference_groot.sh の POLICY_PATH には、Hubのrepo_idか、まだローカルに"
    echo "  残っているチェックポイントがあれば ${GROOT_OUTPUT_DIR}/checkpoints/last/pretrained_model を指定してください。"
    echo "途中から再開する場合（Hubから）:"
    echo "  lerobot-train --config_path=${GROOT_REPO_ID} --resume=true"
elif [ "${SAVE_CHECKPOINT_TO_HUB:-false}" = "true" ]; then
    echo "12_rollout_inference_groot.sh の POLICY_PATH には、ローカルパスとして"
    echo "  ${GROOT_OUTPUT_DIR}/checkpoints/last/pretrained_model"
    echo "を指定してください（Hub上の ${GROOT_REPO_ID} にも各チェックポイントがpushされています）。"
else
    echo "12_rollout_inference_groot.sh の POLICY_PATH には、ローカルパスとして"
    echo "  ${GROOT_OUTPUT_DIR}/checkpoints/last/pretrained_model"
    echo "を指定してください（デフォルトではHubにpushしていません）。"
    echo "後からHubにもpushしたい場合は、例えば以下のようにローカルフォルダをアップロードできます:"
    echo "  hf upload ${GROOT_REPO_ID} ${GROOT_OUTPUT_DIR}/checkpoints/last/pretrained_model --private"
    echo "  (Publicにしたい場合は --private を外してください)"
fi
echo ""
echo "複数GPUで学習する場合は、このスクリプトの lerobot-train の代わりに以下を使ってください（公式ブログ参照）:"
echo '  accelerate launch --multi_gpu --num_processes=$(nvidia-smi -L | wc -l) -m lerobot.scripts.train ...'
