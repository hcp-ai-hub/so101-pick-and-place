#!/usr/bin/env bash
# ============================================================
# 16_interactive_rollout.sh : プロンプト（タスク指示）を対話的に入力しながら
#                              学習済みポリシーで自律動作させる（推論）
#
# 09_rollout_inference.sh / 12_rollout_inference_groot.sh は config.common.env の
# TASK_DESCRIPTION を1つだけ固定で使いますが、このスクリプトは実行のたびに
# ターミナル上でタスク文を打ち直せます（config を毎回書き換えて再実行しなくてよい）。
# ACT/pi0 と GR00T のどちらのトラックでも使え、ループの途中で切り替えられます。
#
# 使い方:
#   ./02_train/16_interactive_rollout.sh              # config.interactive.env の既定トラックを使用
#   ./02_train/16_interactive_rollout.sh groot         # 起動時にトラックを指定 (act / groot)
#   ./02_train/16_interactive_rollout.sh groot ./outputs/train/.../pretrained_model
#                                                       # track=groot 時のみ: ポリシーパスも上書き
#
# ループ中の入力:
#   タスク文をそのまま入力         → そのタスクで1回 lerobot-rollout を実行
#   空Enter                        → 直前と同じタスク文で再実行
#   track act / track groot        → 使用ポリシートラックを切り替え（プロセス再起動不要、
#                                     次に実行するタスクから反映されます）
#   q / quit / exit                → 終了
#   実行中に Ctrl+C                 → そのタスクの実行だけ中断し、次のプロンプト入力に戻ります
#                                     （スクリプト自体は終了しません。終了したい場合は
#                                     プロンプトで 'q' + Enter を入力してください）
#
# ★ 09/12番と同様、ロボットの開始姿勢（レストポーズ）とカメラの位置は、データ収録時
#   (01_collect/06_record_dataset.sh) と必ず揃えてください。ズレているとカメラが作業台を
#   十分に写せず、タスクを認識できないことがあります。詳しくは docs/CAMERA_SETUP.md を参照。
# ★ GR00T (11番) は --policy.use_relative_actions=true で学習しているため、12番と同様に
#   --inference.type=rtc（RTC/チャンク推論パス）を指定しています。
# ============================================================
set -uo pipefail
cd "$(dirname "$0")"

if [ -f "../.venv/bin/activate" ]; then
    source "../.venv/bin/activate"
fi
source ../config.common.env
source ../config.train.env
source ../config.interactive.env

TRACK="${1:-${INTERACTIVE_POLICY_TRACK}}"
POLICY_PATH_OVERRIDE="${2:-}"

CURRENT_TASK="${TASK_DESCRIPTION}"
CURRENT_DURATION="${INTERACTIVE_DEFAULT_DURATION}"

# 1回分の lerobot-rollout をバックグラウンドで起動し、Ctrl+C はその実行だけを
# 中断してループには戻れるようにする（スクリプト全体は落とさない）。
run_rollout() {
    local track="$1"
    local task="$2"
    local duration="$3"
    local policy_path

    case "${track}" in
        act)
            policy_path="${POLICY_PATH_OVERRIDE:-${INTERACTIVE_ACT_POLICY_PATH:-${POLICY_REPO_ID}}}"
            echo "[16_interactive_rollout] track=act policy=${policy_path} duration=${duration}s task=\"${task}\""
            lerobot-rollout \
                --strategy.type=base \
                --policy.path="${policy_path}" \
                --robot.type=so101_follower \
                --robot.port="${FOLLOWER_PORT}" \
                --robot.id="${FOLLOWER_ID}" \
                --robot.cameras="${CAMERA_CONFIG}" \
                --task="${task}" \
                --duration="${duration}" &
            ;;
        groot)
            policy_path="${POLICY_PATH_OVERRIDE:-${INTERACTIVE_GROOT_POLICY_PATH:-${GROOT_REPO_ID}}}"
            echo "[16_interactive_rollout] track=groot policy=${policy_path} duration=${duration}s task=\"${task}\""
            lerobot-rollout \
                --strategy.type=base \
                --policy.path="${policy_path}" \
                --policy.base_model_path="${GROOT_BASE_MODEL_PATH}" \
                --policy.n_action_steps="${GROOT_ROLLOUT_N_ACTION_STEPS}" \
                --robot.type=so101_follower \
                --robot.port="${FOLLOWER_PORT}" \
                --robot.id="${FOLLOWER_ID}" \
                --robot.cameras="${CAMERA_CONFIG}" \
                --task="${task}" \
                --duration="${duration}" \
                --display_data="${DISPLAY_DATA}" \
                --inference.type=rtc \
                --inference.rtc.enabled=true \
                --inference.rtc.execution_horizon="${GROOT_ROLLOUT_N_ACTION_STEPS}" \
                --inference.queue_threshold=0 &
            ;;
        *)
            echo "[16_interactive_rollout] 不明なトラックです: '${track}' ('act' か 'groot' を指定してください)" >&2
            return 1
            ;;
    esac

    local pid=$!
    trap 'echo; echo "[16_interactive_rollout] Ctrl+C: 実行を中断します..."; kill "${pid}" 2>/dev/null; wait "${pid}" 2>/dev/null' INT
    wait "${pid}"
    local status=$?
    trap - INT
    return "${status}"
}

echo "=========================================================="
echo " so101-aist インタラクティブ推論"
echo " 初期トラック: ${TRACK} / 既定タスク: \"${CURRENT_TASK}\" / 既定実行時間: ${CURRENT_DURATION}秒"
echo " 終了するには 'q' + Enter"
echo "=========================================================="

while true; do
    if ! read -r -p $'\n[プロンプト] タスク指示を入力 (空Enter=前回と同じ / track act|groot / q=終了): ' user_input; then
        echo
        echo "[16_interactive_rollout] 入力終了を検知したため終了します。"
        break
    fi

    case "${user_input}" in
        q|quit|exit)
            echo "[16_interactive_rollout] 終了します。"
            break
            ;;
        "track act")
            TRACK="act"
            echo "[16_interactive_rollout] トラックを act に切り替えました。"
            continue
            ;;
        "track groot")
            TRACK="groot"
            echo "[16_interactive_rollout] トラックを groot に切り替えました。"
            continue
            ;;
        "")
            : # 空Enter: 直前の CURRENT_TASK をそのまま使う
            ;;
        *)
            CURRENT_TASK="${user_input}"
            ;;
    esac

    if ! read -r -p "[プロンプト] 実行時間(秒) [空Enter=${CURRENT_DURATION}]: " duration_input; then
        echo
        echo "[16_interactive_rollout] 入力終了を検知したため終了します。"
        break
    fi
    if [ -n "${duration_input}" ]; then
        if ! [[ "${duration_input}" =~ ^[0-9]+$ ]]; then
            echo "[16_interactive_rollout] 数値を入力してください。前回の値(${CURRENT_DURATION}秒)を使います。" >&2
        else
            CURRENT_DURATION="${duration_input}"
        fi
    fi

    if ! run_rollout "${TRACK}" "${CURRENT_TASK}" "${CURRENT_DURATION}"; then
        echo "[16_interactive_rollout] 実行が異常終了、または Ctrl+C で中断されました。次のプロンプトへ進みます。" >&2
    fi
done
