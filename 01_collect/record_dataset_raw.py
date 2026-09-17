#!/usr/bin/env python3
"""
lerobot-record を介さない、生データ収集スクリプト。

- カメラは1台ずつ間隔を空けて接続・リトライする（複数カメラ同時接続時の
  タイムアウト問題を回避する狙い）。
- ロボットの関節角度と各カメラのフレームを、変換・エンコードせずそのまま
  ファイルとして保存するだけ。
- 保存したデータは 15_convert_raw_to_dataset.sh / convert_raw_to_dataset.py で
  後からLeRobotDataset形式に変換する。

このスクリプトは新規に書き下ろしたもので、まだ実機で動作確認できていません。
エラーが出たらそのままメッセージを貼ってください。一緒に直します。
"""
import os
import sys
import json
import time
from pathlib import Path

import cv2
import numpy as np

from lerobot.robots import RobotConfig, make_robot_from_config
from lerobot.teleoperators import TeleoperatorConfig, make_teleoperator_from_config
from lerobot.cameras.opencv import OpenCVCamera, OpenCVCameraConfig

try:
    from lerobot.cameras.realsense import RealSenseCamera, RealSenseCameraConfig
except Exception:
    RealSenseCamera = None
    RealSenseCameraConfig = None


def env(name, default=None, required=False):
    val = os.environ.get(name, default)
    if required and val is None:
        print(f"ERROR: 環境変数 {name} が設定されていません", file=sys.stderr)
        sys.exit(1)
    return val


def build_camera(spec):
    cam_type = spec["type"]
    kwargs = {k: v for k, v in spec.items() if k not in ("name", "type")}
    if cam_type == "opencv":
        return OpenCVCamera(OpenCVCameraConfig(**kwargs))
    elif cam_type in ("intelrealsense", "realsense"):
        if RealSenseCameraConfig is None:
            raise RuntimeError(
                "lerobot.cameras.realsense をインポートできませんでした"
                "（pyrealsense2が未インストールの可能性があります）"
            )
        return RealSenseCamera(RealSenseCameraConfig(**kwargs))
    else:
        raise ValueError(f"未対応のカメラtype: {cam_type}")


def connect_camera_with_retry(name, cam, retries, delay_s):
    last_err = None
    for attempt in range(1, retries + 1):
        try:
            cam.connect()
            print(f"[camera:{name}] connected (attempt {attempt}/{retries})")
            return
        except Exception as e:
            last_err = e
            print(f"[camera:{name}] connect failed (attempt {attempt}/{retries}): {e}")
            time.sleep(delay_s)
    raise RuntimeError(f"[camera:{name}] failed to connect after {retries} attempts") from last_err


def main():
    follower_port = env("FOLLOWER_PORT", required=True)
    follower_id = env("FOLLOWER_ID", required=True)
    leader_port = env("LEADER_PORT", required=True)
    leader_id = env("LEADER_ID", required=True)

    raw_cameras = json.loads(env("RAW_CAMERAS", required=True))
    record_dir = Path(env("RAW_RECORD_DIR", "raw_recordings"))
    fps = float(env("RAW_RECORD_FPS", "30"))
    retries = int(env("RAW_CAMERA_CONNECT_RETRY", "3"))
    connect_delay = float(env("RAW_CAMERA_CONNECT_DELAY_S", "2"))

    num_episodes = int(env("NUM_EPISODES", "5"))
    episode_time_s = float(env("EPISODE_TIME_S", "30"))
    reset_time_s = float(env("RESET_TIME_S", "10"))
    task_description = env("TASK_DESCRIPTION", "")

    session_dir = record_dir / time.strftime("%Y%m%d_%H%M%S")
    session_dir.mkdir(parents=True, exist_ok=True)
    print(f"録画先: {session_dir}")

    # --- カメラを1台ずつ、間隔を空けて接続 ---
    cameras = {}
    for spec in raw_cameras:
        name = spec["name"]
        cam = build_camera(spec)
        connect_camera_with_retry(name, cam, retries, connect_delay)
        cameras[name] = cam
        time.sleep(connect_delay)  # 次のカメラを繋ぐ前にUSBバスを落ち着かせる

    # --- follower をカメラ無しの設定でconnectしてから、手動でカメラを取り付ける ---
    FollowerConfigCls = RobotConfig.get_choice_class("so101_follower")
    follower_cfg = FollowerConfigCls(port=follower_port, id=follower_id, cameras={})
    follower = make_robot_from_config(follower_cfg)
    follower.connect()
    follower.cameras = cameras  # 手動接続済みのカメラを差し込む

    LeaderConfigCls = TeleoperatorConfig.get_choice_class("so101_leader")
    leader_cfg = LeaderConfigCls(port=leader_port, id=leader_id)
    leader = make_teleoperator_from_config(leader_cfg)
    leader.connect()

    manifest = {
        "fps": fps,
        "camera_names": list(cameras.keys()),
        "camera_specs": raw_cameras,
        "task_description": task_description,
        "follower_port": follower_port,
        "follower_id": follower_id,
        "leader_port": leader_port,
        "leader_id": leader_id,
        "episodes": [],
    }

    try:
        for ep_idx in range(num_episodes):
            print(f"\n=== エピソード {ep_idx + 1}/{num_episodes} ===")
            input("準備ができたらEnterを押してください（Ctrl+Cで中断）...")

            ep_dir = session_dir / f"episode_{ep_idx:04d}"
            for cam_name in cameras:
                (ep_dir / cam_name).mkdir(parents=True, exist_ok=True)
            steps_path = ep_dir / "steps.jsonl"

            period = 1.0 / fps
            next_t = time.perf_counter()
            step_idx = 0
            end_t = time.perf_counter() + episode_time_s

            with open(steps_path, "w", encoding="utf-8") as steps_file:
                while time.perf_counter() < end_t:
                    obs = follower.get_observation()
                    action = leader.get_action()
                    follower.send_action(action)

                    step_record = {"step": step_idx, "timestamp": time.time(), "action": {}}
                    for k, v in obs.items():
                        if k in cameras:
                            continue
                        step_record[k] = float(v)
                    for k, v in action.items():
                        step_record["action"][k] = float(v)

                    for cam_name in cameras:
                        frame = obs.get(cam_name)
                        if frame is not None:
                            img_path = ep_dir / cam_name / f"{step_idx:06d}.png"
                            bgr = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR) if frame.ndim == 3 else frame
                            cv2.imwrite(str(img_path), bgr)

                    steps_file.write(json.dumps(step_record) + "\n")

                    step_idx += 1
                    next_t += period
                    sleep_time = next_t - time.perf_counter()
                    if sleep_time > 0:
                        time.sleep(sleep_time)
                    else:
                        next_t = time.perf_counter()

            print(f"エピソード{ep_idx + 1}: {step_idx}ステップ保存しました -> {ep_dir}")
            manifest["episodes"].append({"dir": str(ep_dir.relative_to(session_dir)), "num_steps": step_idx})

            if ep_idx < num_episodes - 1:
                print(f"リセット待機中... {reset_time_s}秒")
                time.sleep(reset_time_s)

    except KeyboardInterrupt:
        print("\n中断されました。ここまでのデータは保存済みです。")
    finally:
        with open(session_dir / "manifest.json", "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)
        for name, cam in cameras.items():
            try:
                cam.disconnect()
            except Exception:
                pass
        try:
            follower.disconnect()
        except Exception:
            pass
        try:
            leader.disconnect()
        except Exception:
            pass

    print(f"\n完了。manifest: {session_dir / 'manifest.json'}")
    print(f"変換するには: RAW_SESSION_DIR={session_dir} ./15_convert_raw_to_dataset.sh")


if __name__ == "__main__":
    main()
