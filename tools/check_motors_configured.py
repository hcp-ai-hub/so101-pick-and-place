#!/usr/bin/env python3
"""
check_motors_configured.py : 6個のモーターが既に正しいIDで設定済みかどうかを
壊さずに（ケーブルを繋ぎ直したりせず、今の数珠つなぎ状態のまま）チェックするツール。

02_setup_motors_follower.sh / 02_setup_motors_leader.sh から呼ばれて、
「うっかり再実行してIDを壊す」事故を防ぐための事前チェックに使います。

各モーター名(shoulder_pan=1 ... gripper=6)に対して、そのIDで応答があるか
1個ずつping()するだけなので、モーター同士を切り離す必要はありません
（IDが重複していれば、そのモーターは自分の割り当てられるはずのIDには
正しく応答できないため、この方法で「既に一意なIDが設定済みか」を安全に
判定できます）。

終了コード:
  0 : 6個全部が期待通りのIDで応答した（＝既に設定済みらしい）
  2 : 1個以上応答しなかった（＝未設定 or 一部壊れている。setup_motorsを実行して問題なし）
  3 : ポートに接続できない等のエラー
"""

import argparse
import sys


def main():
    parser = argparse.ArgumentParser(description="モーターが既に設定済みか安全にチェックする")
    parser.add_argument("--type", choices=["follower", "leader"], required=True)
    parser.add_argument("--port", required=True)
    args = parser.parse_args()

    try:
        if args.type == "follower":
            from lerobot.robots.so_follower import SO101Follower, SO101FollowerConfig

            device = SO101Follower(SO101FollowerConfig(port=args.port, id="_id_check_tmp"))
        else:
            from lerobot.teleoperators.so_leader import SO101Leader, SO101LeaderConfig

            device = SO101Leader(SO101LeaderConfig(port=args.port, id="_id_check_tmp"))

        device.bus.connect(handshake=False)
    except Exception as e:
        print(f"ポート {args.port} に接続できませんでした: {e}")
        sys.exit(3)

    missing = []
    for motor in device.bus.motors:
        model = device.bus.ping(motor, num_retry=1, raise_on_error=False)
        mark = "OK" if model is not None else "見つからない"
        print(f"  {motor} (id={device.bus.motors[motor].id}): {mark}")
        if model is None:
            missing.append(motor)

    device.bus.disconnect(disable_torque=False)

    if not missing:
        print("\n6個全てのモーターが、期待通りのIDで応答しました。既に設定済みの可能性が高いです。")
        sys.exit(0)
    else:
        print(f"\n応答しなかったモーター: {', '.join(missing)} → 未設定、または一部壊れています。")
        sys.exit(2)


if __name__ == "__main__":
    main()
