# so101-aist

SO-101 ロボットアームを **実機で** 動かすためのチュートリアル一式です。
[LeRobot 公式ドキュメント](https://huggingface.co/docs/lerobot/so101) と
[Imitation Learning チュートリアル](https://huggingface.co/docs/lerobot/il_robots) の内容をもとに、
手元で順番に実行できるスクリプトにまとめています。

## 前提

- SO-101 のフォロワーアーム（実際に動くロボット側）と、リーダーアーム（操作用）
  - 参考: [SO-ARM100 README](https://github.com/TheRobotStudio/SO-ARM100)（部品表・3Dプリントデータ）
- Python **>= 3.12**（後述の `uv` が自動で用意してくれるので事前インストール不要）
- 各アームを USB でこのPCに接続
- 全てのスクリプトは、ロボットが繋がっている実機のターミナルで実行してください（USBシリアルポートに直接アクセスするため）

## 環境構築について（uv を使用）

パッケージ管理には [uv](https://docs.astral.sh/uv/) を使います。`uv` は Rust 製の高速なPythonパッケージ/環境マネージャーで、以下のメリットがあります。

- 対応する Python バージョン（3.12）が無くても自動でダウンロードしてくれる（pyenv等が不要）
- 仮想環境の作成 (`uv venv`) とパッケージインストール (`uv pip install`) が高速
- `pip` の代わりに `uv pip` を使うだけで、公式ドキュメントの pip コマンドをそのまま置き換えられる

`00_setup/00_install.sh` を実行すると、このフォルダ直下に `.venv` という仮想環境が作られ、`lerobot[feetech,core_scripts,training]` がインストールされます。**01番以降のスクリプトは `.venv` があれば自動でそれを有効化してから実行する**ようになっているので、毎回手動で `source .venv/bin/activate` する必要はありません（直接コマンドを打ちたい場合のみ手動で有効化してください）。

## ディレクトリ構成 / 実行順序

番号順に実行してください。`config.common.env`（共通設定）を最初に自分の環境に合わせて編集し、データ収集固有の設定は `config.collect.env`、学習固有の設定は `config.train.env` を必要に応じて編集するのがポイントです（3ファイルの詳細は下記「使い方」参照）。

番号付きスクリプト本体は次の3段階でフォルダ分けしています。

- `00_setup/`（一般設定）: アーム・カメラの初期セットアップ（インストール〜キャリブレーション〜テレオペ確認）
- `01_collect/`（データ収集）: データセットの収録・再生・変換
- `02_train/`（学習）: 方策（ACT/pi0/GR00T）の学習と学習済みポリシーでの推論

データ収集〜学習〜推論を一通り行う際の設定項目・コマンド例・再開方法・トラブルシューティングをまとめたガイドは **[docs/PIPELINE_GUIDE.md](./docs/PIPELINE_GUIDE.md)** を参照してください。

また、`fix_motor_id.sh` などのトラブル対応用ツールは
`tools/`、`AGENTS.md`・`CAMERA_SETUP.md` などのドキュメントは `docs/` にまとめています。

| # | スクリプト | 内容 |
|---|-----------|------|
| 0 | `00_setup/00_install.sh` | uv で `.venv` を作成し、LeRobot をインストール |
| 1 | `00_setup/01_find_port.sh` | フォロワー/リーダーの USB ポート名を調べる |
| 2 | `00_setup/02_setup_motors_follower.sh` / `00_setup/02_setup_motors_leader.sh` | 各モーターの ID・ボーレートを設定 |
| 3 | `00_setup/03_calibrate_follower.sh` / `00_setup/03_calibrate_leader.sh` | キャリブレーション（可動域の記録） |
| 4 | `00_setup/04_teleoperate.sh` | リーダーアームでフォロワーアームを操作（テレオペ） |
| 5 | `00_setup/05_teleoperate_with_camera.sh` | カメラ映像を見ながらテレオペ |
| 6 | `01_collect/06_record_dataset.sh` | 操作データ（データセット）を収録し Hugging Face Hub にアップロード |
| 7 | `01_collect/07_replay_episode.sh` | 収録したエピソードをロボットに再生させる |
| 8 | `02_train/08_train_policy.sh` | 収録データで方策（ポリシー）を学習 |
| 9 | `02_train/09_rollout_inference.sh` | 学習済みポリシーで自律動作させる |

### GR00T N1.7 (NVIDIA) を試す場合

pi0よりも新しいVLAとして、[NVIDIA GR00T N1.7](https://huggingface.co/blog/nvidia/nvidia-isaac-teleop-and-gr00t17-in-lerobot) をLeRobot経由でそのまま使えます。08/09番（ACT/pi0系）とは別トラックの10〜12番として用意しています。実行順序は以下の通りです（0〜7番のハード側セットアップ・データ収録は共通です）。

| # | スクリプト | 内容 |
|---|-----------|------|
| 10 | `00_setup/10_install_groot.sh` | GR00T N1.7 を使うための追加パッケージをインストール |
| 11 | `02_train/11_train_policy_groot.sh` | 収録データで GR00T N1.7 をファインチューニング（GPU1枚） |
| 12 | `02_train/12_rollout_inference_groot.sh` | 学習済み GR00T N1.7 ポリシーで自律動作させる |
| 13 | `02_train/13_train_policy_groot_multi_gpu.sh` | 収録データで GR00T N1.7 を複数GPUでファインチューニング |

GR00T N1.7は基本的に `front` + `wrist` の2カメラ構成を前提にしています。カメラの選び方・設置方法・`config.common.env` の書き方・収録時と推論時で開始姿勢を揃える必要がある等の注意点は **[docs/CAMERA_SETUP.md](./docs/CAMERA_SETUP.md)** にまとめてあるので、10番を実行する前に一読してください。

学習マシンにGPUが複数枚ある場合は、11番の代わりに `02_train/13_train_policy_groot_multi_gpu.sh` を使うと LeRobot公式のマルチGPU学習機構（Hugging Face `accelerate`）で学習できます。GPU枚数は `nvidia-smi` から自動検出されます（`config.train.env` の `GROOT_NUM_GPUS` で明示指定も可能）。GPU1枚しか検出できない場合はエラーで停止するので、その場合は11番を使ってください。学習内容（データセット・ポリシー設定）は11番と共通の `config.train.env` の `GROOT_*` 変数を使うため、両者は排他的に使い分けるものです（同時実行はしないでください）。

★ **`02_train/12_rollout_inference_groot.sh` の `--policy.path` に、ファインチューニングしていない生の `nvidia/GR00T-N1.7-3B` を直接指定することはできません**（"config.json not found on the huggingface hub" というエラーになります）。これはLeRobot独自の保存形式とNVIDIA/Isaac-GR00T側の公開形式が違うためで、必ず `02_train/11_train_policy_groot.sh` でファインチューニングして生成したチェックポイント（`${GROOT_OUTPUT_DIR}/checkpoints/last/pretrained_model` またはHubにpushした `GROOT_REPO_ID`）を指定してください。

### 素の (ファインチューニング前の) GR00T-N1.7-3B を試す場合 (実験/検証用)

`10〜12番`は「収録データでファインチューニングしたGR00T」を動かすためのものですが、
「ファインチューニング無しの、公開されたままのGR00T-N1.7-3Bが実機でどう動くか」を
NVIDIA公式のIsaac-GR00Tリポジトリ経由で試す実験用スクリプトを `test/` フォルダに用意しています。
詳細・注意点は **[test/README.md](./test/README.md)** を参照してください
（タスクをこなせることは期待できません。パイプラインの動作確認・興味本位の検証用です）。

### プロンプトを対話的に入力して動かす場合（インタラクティブ推論）

`09_rollout_inference.sh` / `12_rollout_inference_groot.sh` は `config.common.env` の
`TASK_DESCRIPTION` を1つだけ固定で使いますが、実行するたびにタスク文をターミナルで
打ち直したい場合は `02_train/16_interactive_rollout.sh` が使えます（config を毎回
書き換えて再実行する必要がありません）。ACT/pi0・GR00Tどちらのトラックにも対応していて、
ループの途中で `track act` / `track groot` と入力してトラックを切り替えることもできます。

```bash
./02_train/16_interactive_rollout.sh              # config.interactive.env の既定トラックを使用
./02_train/16_interactive_rollout.sh groot         # 起動時にトラックを指定 (act / groot)
```

トラック固有の既定ポリシートラック・実行時間などは新しい `config.interactive.env` にまとまっています
（`POLICY_REPO_ID`/`GROOT_REPO_ID` 自体は引き続き `config.train.env` を参照します）。ループ中の
操作方法（空Enterで再実行、Ctrl+Cでその回だけ中断、`q`で終了 等）はスクリプト冒頭のコメントを
参照してください。

## 使い方

1. `./00_setup/00_install.sh` を実行して `uv` のインストール・`.venv` の作成・LeRobot のインストールを行う
2. `00_setup/01_find_port.sh` を実行してUSBポート名を調べ、`config.common.env` の `FOLLOWER_PORT` / `LEADER_PORT` に書き写す
3. `config.common.env` の他の項目（`HF_USER`、`TASK_DESCRIPTION`、`CAMERA_CONFIG` など）も必要に応じて編集する。
   データ収集専用の設定（`NUM_EPISODES` など）は `config.collect.env`、学習専用の設定（`POLICY_*`、`GROOT_*` など）は
   `config.train.env` にあります。3ファイルとも `HF_PRIVATE` を含みますが、`config.collect.env` は既定 `"true"`
   （収集データはPrivate）、`config.train.env` は既定 `"false"`（学習済みモデルはPublic）と意図的に別の値です。
   タスク文を対話的に入力しながら推論したい場合の設定（既定ポリシートラック・実行時間）は
   `config.interactive.env` にあります（詳細は下記「プロンプトを対話的に入力して動かす場合」を参照）。
4. 番号順にスクリプトを実行していく

```bash
cd so101-aist
./00_setup/00_install.sh
./00_setup/01_find_port.sh
# config.common.env に FOLLOWER_PORT / LEADER_PORT を記入してから続行
./00_setup/02_setup_motors_follower.sh
./00_setup/02_setup_motors_leader.sh
./00_setup/03_calibrate_follower.sh
./00_setup/03_calibrate_leader.sh
./00_setup/04_teleoperate.sh
```

## モーター仕様（参考）

**リーダーアーム**

| 軸 | モーター番号 | ギア比 |
|----|------------|--------|
| Base / Shoulder Pan | 1 | 1/191 |
| Shoulder Lift | 2 | 1/345 |
| Elbow Flex | 3 | 1/191 |
| Wrist Flex | 4 | 1/147 |
| Wrist Roll | 5 | 1/147 |
| Gripper | 6 | 1/147 |

**フォロワーアーム**: STS3215 モーター ×6（ギア比 1/345）

## 安全上の注意

- 初回のテレオペ・自律動作は、周囲に物や人がいない状態で、いつでも電源を切れる状態で行ってください。
- キャリブレーション時は関節をゆっくり動かし、可動域の限界で無理な力をかけないでください。
- カメラを使う場合は `config.common.env` の `CAMERA_CONFIG` をお使いの環境（デバイス番号・解像度）に合わせて調整してください。

## データセット・学習に Hugging Face Hub を使う場合

```bash
hf auth login --add-to-git-credential
HF_USER=$(NO_COLOR=1 hf auth whoami | awk -F': *' 'NR==1 {print $2}')
echo $HF_USER
```

上記で得たユーザー名を `config.common.env` の `HF_USER` に設定してください。

データセット（`01_collect/06_record_dataset.sh`）は `config.collect.env` の `HF_PRIVATE`（デフォルト `"true"`）により
**既定でPrivateリポジトリ**として作成されます。ポリシー（`02_train/08_train_policy.sh`/`02_train/11_train_policy_groot.sh`）は
`config.train.env` の `HF_PRIVATE`（デフォルト `"false"`）により**既定でPublicリポジトリ**として作成されます
—データセットは非公開のまま、学習済みモデルだけ公開する運用です。それぞれのファイルの値を変更すれば挙動を
変えられます。手動で `hf upload` する場合も、各スクリプトの実行結果に表示されるコマンド例に、その時点の
`HF_PRIVATE` の値に応じて `--private` が付きます（外せばPublicになります）。

### 学習チェックポイントの保存先（ローカル / Hub）

`config.train.env` の `SAVE_CHECKPOINT_TO_HUB`（デフォルト `"true"`）と `CHECKPOINT_LOCAL_CLEANUP`
（デフォルト `"true"`）で、学習中に作られるチェックポイントの保存先を制御します。

- `SAVE_CHECKPOINT_TO_HUB="true"`: 最終モデルだけでなく、学習途中の各チェックポイント
  （`save_freq`ごと）も逐次 Hub の `POLICY_REPO_ID`/`GROOT_REPO_ID` にアップロードします
  （`lerobot-train --save_checkpoint_to_hub`）。
- `CHECKPOINT_LOCAL_CLEANUP="true"`: 上記でHubへのアップロードが確認できたローカルの
  チェックポイントディレクトリを、学習と並行してバックグラウンドで自動削除します
  （`tools/checkpoint_hub_gc.py`）。この2つが両方 `true`（既定）の場合、チェックポイントは
  実質的に**Hubにのみ**保存され、ローカルの `outputs/train/.../checkpoints/` には
  ほとんど何も残りません。

  この設定で学習した run を再開する場合は、ローカルの `checkpoints/last` に完全な
  チェックポイントが残っていない前提のため、Hub上のリポジトリを直接指定してください:

  ```bash
  lerobot-train --config_path=${HF_USER}/my_so101_policy --resume=true
  ```

  （`--config_path` はHubの repo_id をそのまま受け付け、`--resume=true` で最新の
  チェックポイントを自動ダウンロードして再開します。）

  ローカルにも普段どおりチェックポイントを残したい場合は `CHECKPOINT_LOCAL_CLEANUP="false"`
  に、Hubへは一切アップロードしたくない場合は `SAVE_CHECKPOINT_TO_HUB="false"` にしてください
  （`false`のときは `CHECKPOINT_LOCAL_CLEANUP` の値に関わらず何も削除しません）。

  手動でクリーンアップだけ実行したい場合は `./tools/checkpoint_hub_gc.sh`（ACTトラック）/
  `./tools/checkpoint_hub_gc.sh groot`（GR00Tトラック）が使えます。

### Weights & Biases (wandb) でログを見る

`config.train.env` の `WANDB_ENABLE` / `GROOT_WANDB_ENABLE`（共にデフォルト `"true"`）で、
`02_train/08_train_policy.sh` / `02_train/11_train_policy_groot.sh` が `lerobot-train` に渡す
`--wandb.enable` を制御します。

認証用の `WANDB_API_KEY`（https://wandb.ai/authorize から取得）は `config.train.env` に
直接記載されており、Git経由でMac・実機Linuxマシン間で共有されます
（ユーザー要望により、`git pull` するだけで各マシンにキーが反映される構成に
しています）。**この構成は、このリポジトリがPrivateであることが前提です。**
Publicにする、または他人をコラボレーターに追加する予定がある場合は、事前に
必ずAPIキーを https://wandb.ai/authorize で再発行し、`config.train.env` を書き換えてください
（古いキーはGitの履歴に残り続けるため、単にファイルから消すだけでは無効化されません）。

wandbを使わない場合は `WANDB_ENABLE="false"` / `GROOT_WANDB_ENABLE="false"` に
してください（`WANDB_API_KEY` はそのままで構いません）。

## トラブルシューティング

- **`SAVE_CHECKPOINT_TO_HUB=true` の学習中にHubへのアップロードでエラー終了する**:
  LeRobot本体の仕様上、学習中の `--save_checkpoint_to_hub` によるアップロードは
  例外処理でガードされていないため、Hubへの接続エラーや認証切れが起きるとその場で
  学習プロセスごと落ちます（ネットワークが不安定な実機マシンでは起きやすい点に注意）。
  `hf auth whoami` で認証が切れていないか、実機マシンのネットワーク疎通を確認してから
  再実行してください。落ちた場合の再開方法は上の「学習チェックポイントの保存先」の
  節を参照してください。
- **`ffmpeg` が見つからない / 動画のデコードエラー**: 動画デコードに TorchCodec が使われ、ffmpeg が必要です。
  `00_setup/00_install.sh` が Mac (Homebrew) / Linux (apt・dnf・pacman) を自動判定してインストールを試みますが、
  失敗する場合はお使いの環境のパッケージマネージャで手動インストールしてください
  （Mac: [Homebrew](https://brew.sh/) 導入後 `brew install ffmpeg` / Linux: 例 `sudo apt-get install ffmpeg`）。
- **学習時のGPU認識**: `config.train.env` の `POLICY_DEVICE=auto`（デフォルト）は `02_train/08_train_policy.sh` 実行時に
  `nvidia-smi` の有無で `cuda`/`cpu` を自動判定します。特定のデバイスを強制したい場合は
  `POLICY_DEVICE` に `cuda` / `cpu` / `mps` などを直接書いてください。
- **`uv: command not found`**: 新しいターミナルを開き直す（`~/.local/bin` にPATHが通っているか確認）か、
  `source $HOME/.local/bin/env` を実行してください。
- **依存関係を作り直したい**: `rm -rf .venv` してから `./00_setup/00_install.sh` を再実行すれば作り直せます。
- **`lerobot-train`/`lerobot-rollout` 実行時に "Your dataset must be tagged with a codebase
  version" エラー**: 通常 `lerobot-record` はアップロード時にHub上のデータセットへ
  `codebase_version`（例: `v3.0`）のgit tagを自動で付けますが、アップロードが失敗して
  `01_collect/06_record_dataset.sh` が案内する手動の `hf upload ...` コマンドでやり直した場合、
  `hf upload` はファイルを置くだけでtagは付けません。`./tools/fix_dataset_tag.sh` を実行すると、
  ローカルにキャッシュされたデータセットの `meta/info.json` から `codebase_version` を
  読み取って、Hub上のリポジトリに同じtagを付け直します
  （`./tools/fix_dataset_tag.sh` は `config.common.env` の `DATASET_REPO_ID` を対象にします。
  別のrepo_idを直したい場合は `./tools/fix_dataset_tag.sh <repo_id>` のように指定してください）。

## モーターIDのトラブル対応

`00_setup/02_setup_motors_follower.sh` / `00_setup/02_setup_motors_leader.sh` は実行前に、既に6個のモーターが
正しいIDで応答しているかを自動チェックします。もし既に設定済みと判定された場合は警告を出し、
`yes` と入力しない限り実行を中止します（うっかり再実行して壊すのを防ぐためです）。

もし一部のモーター（例: ケーブル抜き差しの事故でID 1やID 6だけ）が認識されなくなった場合、
6個全部をやり直す必要はありません。`tools/fix_motor_id.py` / `tools/fix_motor_id.sh` を使えば、
指定した1個のモーターだけIDを設定し直せます。

```bash
./tools/fix_motor_id.sh follower gripper
./tools/fix_motor_id.sh follower shoulder_pan
./tools/fix_motor_id.sh leader gripper
```

## 参考リンク

- SO-101 セットアップ: https://huggingface.co/docs/lerobot/so101
- Imitation Learning チュートリアル: https://huggingface.co/docs/lerobot/il_robots
- インストール手順: https://huggingface.co/docs/lerobot/installation
- uv ドキュメント: https://docs.astral.sh/uv/
- カメラ設定: https://huggingface.co/docs/lerobot/cameras
- カメラ・実環境セットアップ (このリポジトリ, GR00T向け): [docs/CAMERA_SETUP.md](./docs/CAMERA_SETUP.md)
- データセット可視化: https://huggingface.co/spaces/lerobot/visualize_dataset
- LeRobot GitHub: https://github.com/huggingface/lerobot
- GR00T N1.7 × LeRobot × SO-101: https://huggingface.co/blog/nvidia/nvidia-isaac-teleop-and-gr00t17-in-lerobot
- GR00T N1.5 × SO-101 ファインチューニング事例: https://huggingface.co/blog/nvidia/gr00t-n1-5-so101-tuning
