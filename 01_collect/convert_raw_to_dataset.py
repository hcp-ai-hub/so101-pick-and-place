#!/usr/bin/env python3
"""
14_record_dataset_raw.sh で録画した生データ（画像+JSONL）を、正式なLeRobotDataset形式に変換する。

注意: この変換スクリプトは初回実行時にエラーが出る可能性が高いです（LeRobotDatasetの
厳密なfeatureスキーマは、インストールされているlerobotのバージョンに依存するため、
このセッションから確実に検証できていません）。エラーが出たらそのまま貼ってください、
一緒に直します。
"""
import sys
import json
from pathlib import Path

import cv2
import numpy as np

from lerobot.robots import RobotConfig, make_robot_from_config
from lerobot.datasets import LeRobotDataset


def main():
    if len(sys.argv) < 2:
        print("使い方: python3 convert_raw_to_dataset.py <session_dir>")
        sys.exit(1)

    session_dir = Path(sys.argv[1])
    manifest = json.loads((session_dir / "manifest.json").read_text(encoding="utf-8"))

    camera_names = manifest["camera_names"]
    fps = manifest["fps"]
    task_description = manifest.get("task_description") or "so101 teleoperation"

    import os
    repo_id = os.environ.get("DATASET_REPO_ID")
    if not repo_id:
        print("ERROR: 環境変数 DATASET_REPO_ID が設定されていません（config.common.envで定義済みのはずです）")
        sys.exit(1)
    private_env = os.environ.get("HF_PRIVATE", "true").lower() == "true"

    # カメラ込みのfollower設定を再構築して observation_features / action_features を取得する
    # (ハードウェアには接続しない。スキーマ情報だけが必要)
    FollowerConfigCls = RobotConfig.get_choice_class("so101_follower")
    camera_cfgs = {}
    for spec in manifest["camera_specs"]:
        name = spec["name"]
        camera_cfgs[name] = {k: v for k, v in spec.items() if k not in ("name",)}
    follower_cfg = FollowerConfigCls(
        port=manifest["follower_port"], id=manifest["follower_id"], cameras=camera_cfgs
    )
    follower = make_robot_from_config(follower_cfg)

    features = {}
    for key, spec in follower.observation_features.items():
        if key in camera_names:
            continue  # 画像は別途videoとして下で定義
        features[f"observation.{key}"] = {"dtype": "float32", "shape": (1,), "names": None}
    for key in follower.action_features:
        features[f"action.{key}"] = {"dtype": "float32", "shape": (1,), "names": None}
    for cam_name in camera_names:
        spec = next(s for s in manifest["camera_specs"] if s["name"] == cam_name)
        h, w = spec.get("height", 480), spec.get("width", 640)
        features[f"observation.images.{cam_name}"] = {
            "dtype": "video",
            "shape": (h, w, 3),
            "names": ["height", "width", "channels"],
        }

    print("構築したfeatures:")
    for k, v in features.items():
        print(f"  {k}: {v}")

    dataset = LeRobotDataset.create(
        repo_id,
        fps,
        robot_type="so101_follower",
        features=features,
        use_videos=True,
    )

    for ep in manifest["episodes"]:
        ep_dir = session_dir / ep["dir"]
        steps = [json.loads(line) for line in (ep_dir / "steps.jsonl").read_text(encoding="utf-8").splitlines()]
        for step in steps:
            frame = {}
            for key, val in step.items():
                if key in ("step", "timestamp", "action"):
                    continue
                frame[f"observation.{key}"] = np.float32(val)
            for key, val in step["action"].items():
                frame[f"action.{key}"] = np.float32(val)
            for cam_name in camera_names:
                img_path = ep_dir / cam_name / f"{step['step']:06d}.png"
                bgr = cv2.imread(str(img_path))
                rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
                frame[f"observation.images.{cam_name}"] = rgb
            frame["task"] = task_description
            dataset.add_frame(frame)
        dataset.save_episode()
        print(f"エピソード {ep['dir']} を変換しました（{len(steps)}ステップ）")

    try:
        dataset.push_to_hub(private=private_env)
        print(f"HF Hubにpushしました: {repo_id} (private={private_env})")
    except Exception as e:
        print(f"HF Hubへのpushに失敗しました（ローカルには保存済みです）: {e}")

    print("変換完了。")


if __name__ == "__main__":
    main()
