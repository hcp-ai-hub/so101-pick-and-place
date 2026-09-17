# データ収集 → 学習 → 推論ガイド

`00_setup/` でアーム・カメラのセットアップが終わった後、`01_collect/` でデータセットを収録し、
`02_train/` で方策を学習して、学習済みポリシーで実機を自律動作（推論）させるまでの一連の流れを
まとめたドキュメントです。個々のスクリプトの詳細は [README.md](../README.md)、環境固有の
トラブルは [AGENTS.md](./AGENTS.md)・[CAMERA_SETUP.md](./CAMERA_SETUP.md) も参照してください。

## 0. 前提条件

- `00_setup/00_install.sh`（ACT/pi0の場合）または `00_setup/00_install.sh` + `00_setup/10_install_groot.sh`
  （GR00Tの場合）で `.venv` を構築済み
- `00_setup/01_find_port.sh` 〜 `00_setup/05_teleoperate_with_camera.sh` でポート設定・
  モーターキャリブレーション・テレオペ確認が済んでいること
- 学習は実質GPU必須（`POLICY_DEVICE=auto`は`torch.cuda.is_available()`が`False`だとCPUに
  黙ってフォールバックせずエラー終了する仕様）

## 1. データ収集（`01_collect/`）

### 1.1 収録前に確認する設定

`config.common.env`（収集・学習共通）:

| 変数 | 説明 |
|---|---|
| `DATASET_REPO_ID` | 収録したデータセットのHub repo_id（学習側もここを見て読み込む） |
| `TASK_DESCRIPTION` | タスクの説明文（収録・推論の両方で使う） |
| `CAMERA_CONFIG` | `lerobot-record`/`lerobot-rollout`に渡すカメラ構成（辞書構文） |
| `DISPLAY_DATA` | `true`にすると収録中の映像をrerunでリアルタイム表示（実機にディスプレイが無い場合は`false`のまま） |

`config.collect.env`（収集専用）:

| 変数 | 既定値 | 説明 |
|---|---|---|
| `HF_PRIVATE` | `true` | 収録したデータセットをHubにPrivateでアップロードするか |
| `NUM_EPISODES` | `50` | 収録するエピソード数 |
| `EPISODE_TIME_S` | `60` | 1エピソードあたりの収録時間（秒） |
| `RESET_TIME_S` | `60` | エピソード間のリセット（手動で初期姿勢に戻す）時間（秒） |

### 1.2 収録を実行する

事前に `hf auth login --add-to-git-credential` でログインしておいてください。

```bash
./01_collect/06_record_dataset.sh
```

収録中のキー操作:

- `→` または `n`: 現在のエピソードを早期終了して次へ
- `←` または `r`: このエピソードをやり直す（再収録）
- `ESC` または `q`: 収録セッションを終了し、動画をエンコードしてアップロード

収録データはローカル（`~/.cache/huggingface/lerobot/${DATASET_REPO_ID}`）にも残ります。
アップロードが失敗した場合は、スクリプトの実行結果に表示される`hf upload`コマンドで
手動アップロードできます（ただしその場合`codebase_version`のtagが付かないため、
`lerobot-train`/`lerobot-rollout`で「dataset must be tagged with a codebase version」
エラーが出たら`./tools/fix_dataset_tag.sh`でtagを付け直してください）。

### 1.3 収録したエピソードを確認する

```bash
./01_collect/07_replay_episode.sh [エピソード番号(省略時は0)]
```

指定したエピソードの記録済み軌道をフォロワーアームにそのまま再生させ、収録内容が
正しいか目視確認できます。

### 1.4 代替経路: カメラを1台ずつ接続して収録する（`lerobot-record`が使えない場合）

RealSense + OpenCVカメラの同時接続でwristカメラがtimeoutするなど、`lerobot-record`での
複数カメラ同時収録がうまくいかない環境向けの代替手段です（詳細は
[CAMERA_SETUP.md](./CAMERA_SETUP.md) 参照）。カメラを1台ずつ間隔を空けて接続しながら、
生データ（画像+関節角度JSON）をそのまま保存し、後から正式なLeRobotDataset形式に変換します。

```bash
./01_collect/14_record_dataset_raw.sh
RAW_SESSION_DIR=raw_recordings/20260907_153000 ./01_collect/15_convert_raw_to_dataset.sh
```

- `14`は`config.common.env`の`RAW_CAMERAS`（`CAMERA_CONFIG`と同じ内容をJSON配列で書いたもの）
  ・`RAW_RECORD_DIR`・`RAW_RECORD_FPS`・`RAW_CAMERA_CONNECT_RETRY`/`_DELAY_S`を使います。
  保存先は`01_collect/${RAW_RECORD_DIR}`以下に日時付きセッションフォルダができます。
- `15`は`14`が保存したセッションフォルダ（`RAW_SESSION_DIR`）を指定して実行し、
  `config.collect.env`の`HF_PRIVATE`に従ってHubにアップロードします。

## 2. トラックを選ぶ（学習）

| トラック | 学習スクリプト | 推論スクリプト | 備考 |
|---|---|---|---|
| ACT / pi0 | `02_train/08_train_policy.sh` | `02_train/09_rollout_inference.sh` | `config.train.env`の`POLICY_TYPE`（既定`act`）を使う本線 |
| GR00T N1.7（単体GPU） | `02_train/11_train_policy_groot.sh` | `02_train/12_rollout_inference_groot.sh` | 要 `00_setup/10_install_groot.sh` |
| GR00T N1.7（複数GPU） | `02_train/13_train_policy_groot_multi_gpu.sh` | `02_train/12_rollout_inference_groot.sh` | `accelerate`使用。GPU1枚しか検出できない場合はエラーで停止するので11番を使うこと |

11番と13番は同じ`config.train.env`の`GROOT_*`設定を共有する「同じ学習内容の別実行方法」なので、
同時実行はしないでください。

## 3. 学習前に確認する設定（`config.train.env`）

| 変数 | 既定値 | 説明 |
|---|---|---|
| `HF_PRIVATE` | `false` | 学習済みポリシーをHubにPublicで上げるか（データセット側は`config.collect.env`で別管理） |
| `POLICY_TYPE` | `act` | ACT/pi0トラックで使うポリシー種別 |
| `POLICY_DEVICE` | `auto` | `auto`はCUDA利用可否を自動判定し、不可ならエラー終了。明示指定するなら`cuda`/`cpu`/`mps` |
| `POLICY_REPO_ID` / `GROOT_REPO_ID` | `${HF_USER}/my_so101_policy_v2` 等 | 学習済みポリシーのHub repo_id |
| `OUTPUT_DIR` / `GROOT_OUTPUT_DIR` | `outputs/train/...`（`02_train/`基準の相対パス） | ローカルの学習出力先 |
| `WANDB_ENABLE` / `GROOT_WANDB_ENABLE` | `true` | wandbロギングを使うか。認証は`WANDB_API_KEY`（Gitで共有しているのでPrivateリポジトリ前提） |
| `SAVE_CHECKPOINT_TO_HUB` | `true` | 学習中の各チェックポイントも逐次Hubにアップロードするか |
| `CHECKPOINT_LOCAL_CLEANUP` | `true` | Hubへのアップロードが確認できたローカルチェックポイントを自動削除するか（両方`true`だと実質Hubのみ保存） |
| `GROOT_NUM_GPUS` | 空文字（自動検出） | 13番専用。複数GPU学習で使うGPU枚数を絞りたい場合に指定 |

## 4. 学習を実行する

### ACT / pi0

```bash
./02_train/08_train_policy.sh
```

内部的には次のような`lerobot-train`呼び出しになります（値は`config.common.env`/`config.train.env`から）。

```bash
lerobot-train \
    --dataset.repo_id="${DATASET_REPO_ID}" \
    --policy.type="${POLICY_TYPE}" \
    --output_dir="${OUTPUT_DIR}" \
    --job_name="${JOB_NAME}" \
    --policy.device="${RESOLVED_DEVICE}" \
    --policy.repo_id="${POLICY_REPO_ID}" \
    --policy.private="${HF_PRIVATE}" \
    --save_checkpoint_to_hub="${SAVE_CHECKPOINT_TO_HUB}" \
    --wandb.enable="${WANDB_ENABLE}"
```

### GR00T N1.7（単体GPU）

```bash
./02_train/11_train_policy_groot.sh
```

- 既定でHugging Face Hubにオンラインアクセスします（`HF_HUB_OFFLINE=0`）。ベースモデル
  `nvidia/GR00T-N1.7-3B` はgatedモデルなので、初回は事前に
  [モデルページ](https://huggingface.co/nvidia/GR00T-N1.7-3B) で利用規約に同意し、
  `hf auth login --add-to-git-credential` を済ませておいてください。
  一度ローカルにキャッシュされれば `HF_HUB_OFFLINE=1 ./02_train/11_train_policy_groot.sh` で
  オフライン学習もできます。
- `--policy.use_relative_actions=true` で学習するため、推論時は後述のRTC推論パスが必要になります。

### GR00T N1.7（複数GPU）

```bash
./02_train/13_train_policy_groot_multi_gpu.sh
```

- 11番と同じ`GROOT_*`設定を使い、`accelerate launch --multi_gpu --num_processes=<GPU枚数>`で起動します。
- GPU枚数は既定で`nvidia-smi -L | wc -l`から自動検出（`GROOT_NUM_GPUS`で上書き可）。
  1枚以下しか検出できない場合はエラーで停止するので、その場合は11番を使ってください。

### 学習中の挙動（共通）

- `POLICY_DEVICE=auto`はCUDAが実際に使えるかを`torch.cuda.is_available()`で判定し、
  使えない場合は黙ってCPUにフォールバックせずエラー終了します
  （CPUで意図的に学習したい場合のみ`POLICY_DEVICE=cpu`を明示指定）。
- `SAVE_CHECKPOINT_TO_HUB=true` かつ `CHECKPOINT_LOCAL_CLEANUP=true`（既定）の場合、
  `tools/checkpoint_hub_gc.py` が学習と並行してバックグラウンドで起動し、
  Hubへのアップロードが確認できたローカルのチェックポイントを自動削除します。

### 中断からの再開

- `CHECKPOINT_LOCAL_CLEANUP=true`でHubのみに保存している場合:
  ```bash
  lerobot-train --config_path=<HF_USER>/<POLICY_REPO_ID または GROOT_REPO_ID> --resume=true
  ```
- ローカルにチェックポイントが残っている場合:
  ```bash
  lerobot-train --config_path=<OUTPUT_DIR>/checkpoints/last/pretrained_model/train_config.json --resume=true
  ```
  （13番でHubから複数GPUのまま再開したい場合は、13番自体を再実行してください）

## 5. 推論（rollout）を実行する

### ACT / pi0

```bash
./02_train/09_rollout_inference.sh [動作時間(秒), 省略時60]
```

`POLICY_REPO_ID`（Hub上の学習済みポリシー）を`--policy.path`にそのまま渡して実行します。

### GR00T N1.7

```bash
./02_train/12_rollout_inference_groot.sh                                      # Hub上の GROOT_REPO_ID を使う
./02_train/12_rollout_inference_groot.sh 60 outputs/train/.../pretrained_model # ローカルckptを使う
```

- 第1引数: 動作時間（秒、省略時60）／第2引数: `--policy.path`を上書き（省略時`GROOT_REPO_ID`）
- **★ロボットの開始姿勢（レストポーズ）とカメラの位置は、収録時（`01_collect/06_record_dataset.sh`実行時）
  と必ず揃えてください。** ズレているとカメラが作業台を十分に写せず、タスクを認識できないことがあります。
  詳しくは [CAMERA_SETUP.md](./CAMERA_SETUP.md) を参照してください。
- 11番は`--policy.use_relative_actions=true`で学習するため、通常の推論パスでは
  `NotImplementedError`になります。これを避けるため`12_rollout_inference_groot.sh`は
  `--inference.type=rtc`（RTC/チャンク推論パス）を指定済みです。

### インタラクティブ推論（プロンプトを都度入力する）

タスク文（プロンプト）を`config.common.env`の`TASK_DESCRIPTION`に固定せず、実行のたびに
ターミナルで入力したい場合は`02_train/16_interactive_rollout.sh`を使います。

```bash
./02_train/16_interactive_rollout.sh              # config.interactive.env の既定トラックを使用
./02_train/16_interactive_rollout.sh groot         # 起動時にトラックを指定 (act / groot)
./02_train/16_interactive_rollout.sh groot ./outputs/train/.../pretrained_model  # ローカルckptも指定
```

- タスク文を入力するとそのタスクで1回`lerobot-rollout`を実行し、終わると次のタスクを
  聞くループになります（空Enterで直前と同じタスクを再実行、実行時間も空Enterで前回値を使用）。
- ループの途中で`track act`/`track groot`と入力すればトラックを切り替えられます
  （プロセスは再起動されず、次に実行するタスクから反映されます）。
- 実行中に`Ctrl+C`するとその回の実行だけを中断してプロンプト入力に戻ります。終了するには
  プロンプトで`q`（または`quit`/`exit`）を入力してください。
- 各トラックの`--policy.path`は既定で`config.train.env`の`POLICY_REPO_ID`/`GROOT_REPO_ID`を
  使いますが、`config.interactive.env`の`INTERACTIVE_ACT_POLICY_PATH`/`INTERACTIVE_GROOT_POLICY_PATH`
  （またはコマンドライン第2引数、groot時のみ）で上書きできます。
- 上記のロボット開始姿勢・カメラ位置の注意点、GR00Tの`--inference.type=rtc`指定は
  09番/12番と同じくそのまま当てはまります。

## 6. トラブルシューティング（データ収集・学習・推論固有）

- **収録時にwristカメラだけtimeoutする**: RealSense + OpenCVカメラの同時接続に起因する
  既知の問題です。[CAMERA_SETUP.md](./CAMERA_SETUP.md)の該当節、または上記1.4の
  「カメラを1台ずつ接続する代替経路（14/15番）」を試してください。
- **`hf upload`で手動アップロードした後に「dataset must be tagged with a codebase version」
  エラー**: `hf upload`はファイルを置くだけでtagを付けないため。`./tools/fix_dataset_tag.sh`
  を実行してtagを付け直してください。
- **`torch.cuda.is_available()` = False でエラー終了する**: `nvidia-smi`がGPUを検出しているのに
  このエラーが出る場合、CPU専用ビルドのtorchが入っている／ドライバとCUDAランタイムの
  バージョン不整合／`CUDA_VISIBLE_DEVICES`の設定などが考えられます（スクリプトが診断情報を出力します）。
- **GR00Tのベースモデルがダウンロードできない（オフラインモード時）**: `nvidia/GR00T-N1.7-3B`は
  gatedモデルのため、`HF_HUB_OFFLINE=1`のままだと初回ダウンロードができません。一度
  `HF_HUB_OFFLINE=0`でオンライン実行してローカルにキャッシュしてから、オフラインに切り替えてください。
- **GR00T推論で`GrootPolicy.select_action does not support relative-action policies`**:
  `11_train_policy_groot.sh`が`use_relative_actions=true`で学習しているため。`12番`は
  `--inference.type=rtc`を指定済みなので、素の`lerobot-rollout`を直接叩く場合は同様のRTC指定を追加してください。
- **13番（複数GPU）が「GPU1枚しか検出できない」で停止する**: 単体GPU用の11番を使ってください。
- **学習済みポリシーのHub公開範囲を変えたい**: `config.train.env`の`HF_PRIVATE`を編集してください
  （データセット側は`config.collect.env`の`HF_PRIVATE`で別管理、既定でPrivate）。
- その他の一般的なトラブル（`ffmpeg`、`uv`、モーターIDなど）は
  [README.md](../README.md)の「トラブルシューティング」節を参照してください。
