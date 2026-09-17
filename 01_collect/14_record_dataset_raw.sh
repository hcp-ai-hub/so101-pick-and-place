#!/bin/bash
# lerobot-record を使わず、カメラを1台ずつ間隔を空けて接続しながら
# 生データ（画像+関節角度JSON）だけをそのまま保存するスクリプト。
#
# RealSense + OpenCVカメラの同時接続でwristカメラがtimeoutする問題
# (LeRobot側の既知の未解決バグの可能性、docs/CAMERA_SETUP.md参照)を
# 回避するための代替手段。
#
# 録画が終わったら 15_convert_raw_to_dataset.sh で正式なLeRobotDataset
# 形式に変換してください。
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../.venv/bin/activate
source ../config.common.env
python3 record_dataset_raw.py
