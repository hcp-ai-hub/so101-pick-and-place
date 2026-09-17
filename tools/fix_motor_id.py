#!/usr/bin/env python3
"""
fix_motor_id.py : SO-101アームの特定モーター1個だけ、IDを設定し直すツール

02_setup_motors_follower.sh / 02_setup_motors_leader.sh は6個のモーター
(gripper, wrist_roll, wrist_flex, elbow_flex, shoulder_lift, shoulder_pan)
を毎回順番に全部設定し直しますが、これは指定したモーター1個だけをやり直せます。
「間違えてsetup_motorsを実行したら特定のIDだけ壊れた（認識されなくなった）」
というときに使ってください。

内部的には lerobot の MotorsBus.setup_motor() を直接呼んでいます。
これは lerobot-setup-motors (= 02_*.sh) が6モーター分ループしながら
呼んでいるのと同じ関数を、1個分だけ呼び出しているだけです。

使い方の例:
  # フォロワーの gripper (ID=6) だけやり直す
  python fix_motor_id.py --type=follower --port=/dev/ttyACM1 --motor=gripper

  # フォロワーの shoulder_pan (ID=1) だけやり直す
  python fix_motor_id.py --type=follower --port=/dev/ttyACM1 --motor=shoulder_pan

  # リーダー側も同様に --type=leader で
  python fix_motor_id.py --type=leader --port=/dev/ttyACM0 --motor=gripper

モーター名とID番号の対応（so101_follower / so101_leader 共通）:
  1: shoulder_pan   2: shoulder_lift   3: elbow_flex
  4: wrist_flex     5: wrist_roll      6: gripper

実行すると「controller boardを '<motor>' モーターだけに接続してEnter」と
出るので、02_setup_motors_*.sh の時と同じように、そのモーター1個だけを
controller boardに接続した状態でEnterを押してください。
"""

import argparse

MOTOR_NAMES = [
    "shoulder_pan",
    "shoulder_lift",
    "elbow_flex",
    "wrist_flex",
    "wrist_roll",
    "gripper",
]


def main():
    parser = argparse.ArgumentParser(description="SO-101の特定モーター1個だけIDを設定し直す")
    parser.add_argument("--type", choices=["follower", "leader"], required=True, help="follower または leader")
    parser.add_argument("--port", required=True, help="config.common.env の FOLLOWER_PORT または LEADER_PORT")
    parser.add_argument("--motor", required=True, choices=MOTOR_NAMES, help="やり直したいモーター名")
    parser.add_argument("--id", default=None, help="キャリブレーションファイル名に使うID。省略可（このスクリプトでは実質使いません）")
    args = parser.parse_args()

    if args.type == "follower":
        from lerobot.robots.so_follower import SO101Follower, SO101FollowerConfig

        device = SO101Follower(SO101FollowerConfig(port=args.port, id=args.id))
    else:
        from lerobot.teleoperators.so_leader import SO101Leader, SO101LeaderConfig

        device = SO101Leader(SO101LeaderConfig(port=args.port, id=args.id))

    input(f"\ncontroller boardを '{args.motor}' モーターだけに接続してEnterを押してください。")
    device.bus.setup_motor(args.motor)
    print(f"'{args.motor}' のIDを {device.bus.motors[args.motor].id} に設定しました。")
    print("他のモーターは変更していません。全部の接続を元の数珠つなぎに戻して問題ありません。")


if __name__ == "__main__":
    main()
