#!/bin/bash
# 14_record_dataset_raw.sh で保存した生データを、正式なLeRobotDataset形式
# （LeRobotDataset.create -> add_frame -> save_episode）に変換するスクリプト。
#
# 使い方:
#   RAW_SESSION_DIR=raw_recordings/20260907_153000 ./01_collect/15_convert_raw_to_dataset.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../.venv/bin/activate
source ../config.common.env
source ../config.collect.env
if [ -z "$RAW_SESSION_DIR" ]; then
  echo "使い方: RAW_SESSION_DIR=raw_recordings/20260907_153000 ./01_collect/15_convert_raw_to_dataset.sh"
  exit 1
fi
python3 convert_raw_to_dataset.py "$RAW_SESSION_DIR"
