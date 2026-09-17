# AGENTS.md — so101-aist

このフォルダはSO-101ロボットアーム（LeRobot）を実機で動かすためのチュートリアルスクリプト集です。
何か作業する前に、必ず以下の背景情報を確認してください。

**フォルダ構成（2026-09-09整理）**: 番号付きパイプラインスクリプト（`00_setup/00_install.sh`〜`01_collect/15_convert_raw_to_dataset.sh`）と
`.venv`はこのファイル（`docs/AGENTS.md`）から見て一つ上の`so101-aist/`直下にある。
`fix_motor_id.*`/`fix_dataset_tag.*`/`checkpoint_hub_gc.*`/`check_motors_configured.py`は`tools/`、
このファイルと`CAMERA_SETUP.md`は`docs/`に置いてある。今後スクリプトを追加するときもこの分類に従うこと
（パイプライン本体は番号付きでルート直下、随時使う診断・修復ツールは`tools/`）。

**設定ファイルの3分割（2026-09-09、ユーザー要望）**: `config.env`（単一ファイル）は廃止し、
`config.common.env`（ポート・アームID・HF_USER・DATASET_REPO_ID・TASK_DESCRIPTION・CAMERA_CONFIG・
RAW_CAMERAS等、収集/学習どちらでも使う設定）、`config.collect.env`（`01_collect/06_record_dataset.sh`/
`01_collect/15_convert_raw_to_dataset.sh`用。NUM_EPISODES等に加え`HF_PRIVATE="true"`）、
`config.train.env`（08/09/11/12/13番と`tools/checkpoint_hub_gc.sh`用。POLICY_*/GROOT_*/WANDB_*/
CHECKPOINT_*に加え`HF_PRIVATE="false"`）の3ファイルに分割した。**`HF_PRIVATE`が
collect側=true・train側=falseと意図的に別の値なのはバグではない** — データセットは非公開のまま、
学習済みポリシーだけ公開する運用をユーザーが希望したため。各スクリプトは役割に応じて
`config.common.env`に加えて`config.collect.env`または`config.train.env`のどちらか一方だけをsourceする
（両方を同時にsourceするスクリプトは無い — HF_PRIVATEの値が衝突するため）。新しいスクリプトを
追加するときも、収集/学習どちらの役割かでsource元を選ぶこと。

## 実行環境について（最重要）

このファイル群は Mac（mac-internal2）上の `aist/so101-aist` に置かれていますが、
**実機（フォロワーアーム・リーダーアーム・カメラ・USBシリアルポート）は全て別のLinuxマシンに接続されており、
スクリプトも全部そのLinuxマシン上のターミナルで実行されています。**Macはあくまでファイルの綘集倴所（Claudeのdevice_bashが观mる場所）であり、
学習・推論を含めた実際の処理は一切Mac上では行われません。

このフォルダを編集しても、Linuxマシン側に同期（コピー）されるまでは実機には反映されません。
編集後は必ず「Linux機に同期してから実行してください」とユーザーに伝えること。

## 現在分かっているポート・設定

- `FOLLOWER_PORT=/dev/ttyACM1`, `LEADER_PORT=/dev/ttyACM0`（`config.common.env`に設定済み。USBの挿し直しで変わる可能性あり）
- 電源電圧はフォロワーとリーダーで別物: **リーダーは5V、フォロワーは12V**。逆に挿すとモーターを壊す恐れがあるので、
  電源関連のトラブルシュートをするときはこの違いを必ず確認すること。
- `POLICY_DEVICE=auto`（`config.train.env`）: `02_train/08_train_policy.sh`/`02_train/11_train_policy_groot.sh`が判定する。
  以前は`nvidia-smi`の有無だけで判定していたが、それだと「nvidia-smiは動くのに.venvのtorchからは
  CUDAが見えない」ケースを見逃すため、`python -c "import torch; torch.cuda.is_available()"`で判定するよう変更済み。
  さらにCUDAが使えない場合は`cpu`に黙ってフォールバックせず`exit 1`でエラー終了する（2026-09-01変更、
  ユーザー要望「学習時はgpu以外はエラーでいいよ」）。意図的にCPUで動かしたい場合のみ`POLICY_DEVICE=cpu`を明示指定する。
  Apple Silicon固有の`mps`はもう使っていない（実機がLinuxのため）。
- `02_train/13_train_policy_groot_multi_gpu.sh`（2026-09-02追加、ユーザー要望「複数枚学習用のスクリプトを別に書いて」）: `02_train/11_train_policy_groot.sh`と同じ`config.train.env`のGROOT_*設定を使い、LeRobot公式のマルチGPU機構（`accelerate launch --multi_gpu --num_processes=<GPU枚数>`、参考: https://huggingface.co/docs/lerobot/multi_gpu_training）で起動する版。GPU枚数は既定で`nvidia-smi -L | wc -l`から自動検出（`config.train.env`の`GROOT_NUM_GPUS`で上書き可）、検出/指定が1枚以下ならエラーで停止して11番の利用を促す。accelerateの`--mixed_precision`は既定`"no"`（`GROOT_MULTI_GPU_MIXED_PRECISION`で変更可）— GR00Tポリシー自体が`--policy.use_bf16=true`で独自にbf16キャストするため、二重キャストを避けるため。`--batch_size`はプロセス（GPU）ごとの値で、実効バッチサイズは`GROOT_BATCH_SIZE × GPU枚数`になる点、学習率/ステップ数はGPU枚数に応じて自動スケーリングされない点に注意（accelerateの仕様）。
  なお、NVIDIA本家のIsaac-GR00Tリポジトリ自身（`scripts/gr00t_finetune.py --num-gpus`、`torchrun`+DeepSpeed経由）にも別のマルチGPU学習パスがあるが、こちらはLeRobot経由の学習
  （`so101-aist`が使っている方）とは別物で、13番はLeRobot側（accelerate経由）の方を採用している。
- `00_setup/00_install.sh`のffmpegインストールはOS自動判定（Mac=brew, Linux=apt-get/dnf/pacman）。
- `HF_PRIVATE`: 2026-09-02にユーザー要望「基本的にHFへのアップロードはPrivateで行いたい」で追加、
  2026-09-09に`config.collect.env`（`01_collect/06_record_dataset.sh`の`--dataset.private`、既定`"true"`）と
  `config.train.env`（`02_train/08_train_policy.sh`/`02_train/11_train_policy_groot.sh`/`13...`の`--policy.private`、
  既定`"false"`）に分割済み——ユーザーが「収集データはPrivateのまま、学習済みモデルはPublicにしたい」と
  明示したため、**この2値が異なるのは意図的**（バグとして揃えないこと）。LeRobot側のデフォルトはPublic相当
  （`private`未指定＝アカウント/組織の既定に依存）なので、明示的に`--dataset.private`/`--policy.private`を
  渡すようにしている。手動`hf upload`の場合も06/11番スクリプトの案内メッセージに、その時点の`HF_PRIVATE`
  の値に応じて`--private`を付けてある。正当な理由なくどちらの既定も外さないこと。
- `SAVE_CHECKPOINT_TO_HUB`/`CHECKPOINT_LOCAL_CLEANUP`（`config.train.env`、共にデフォルト`"true"`）:
  2026-09-02、ユーザー要望「チェックポイントをリモートのみに保存したい」で追加。
  `02_train/08_train_policy.sh`/`02_train/11_train_policy_groot.sh`は`lerobot-train`に`--save_checkpoint_to_hub`
  を渡し（学習途中の各チェックポイントもHubの`POLICY_REPO_ID`/`GROOT_REPO_ID`へ逐次push）、
  かつ両スクリプトが`tools/checkpoint_hub_gc.py`をバックグラウンドで並行起動して、Hub上に同名tagが
  確認できたローカルチェックポイントだけを自動削除する（新規追加した`tools/checkpoint_hub_gc.py`/
  `.sh`）。lerobot-train自体には「ローカルに書かずに直接Hubへ」という機能が無い
  （`save_checkpoint()`でローカル保存 → 直後に同一プロセス内で同期的に`push_checkpoint_to_hub()`
  という順序がライブラリ内に固定されている）ため、GCスクリプトによる後追い削除という形にした。
  ユーザーには「Hub到達が確認できるまでは削除しない」代わりに「クラッシュ時の再開はローカルの
  `checkpoints/last`ではなくHubの`--config_path=<repo_id> --resume=true`から行う」というトレード
  オフがあることを明示的に説明し、了承を得た上で実装（ローカルに何も残さない案と、Hubにも
  push するがローカルはそのまま残す案の2択を提示し、前者を選択）。
  `--save_checkpoint_to_hub`はlerobot本体でも例外処理でガードされておらず、Hub接続/認証エラーで
  学習プロセスごと落ちる仕様のため、その旨README.mdのトラブルシューティングに追記済み。
- `WANDB_ENABLE`/`GROOT_WANDB_ENABLE`（`config.train.env`、2026-09-02にユーザーがwandb APIキーを
  提供したのを受けてデフォルトを`"true"`に変更、以前は08は未配線・GROOT側は`"false"`だった）:
  `02_train/08_train_policy.sh`/`02_train/11_train_policy_groot.sh`の`--wandb.enable`に渡す。
  `WANDB_API_KEY`は**`config.train.env`に直接平文で記載してあり、Gitにコミット・push済み**
  （2026-09-09の設定3分割で`config.env`から移動、扱いは変わらず）。
  最初は`config.local.env`（`.gitignore`済み・Git管理外）に分離していたが、
  ユーザーから明示的に「pullして使い回したいのでリモートに上げてくれ」と要望があり、
  それに従って2026-09-02にconfig.envへ統合し直した（config.local.env/.exampleは削除）。
  **これは意図的なユーザー判断であり、勝手に`config.local.env`方式に戻したり、
  正当な理由なくAPIキーをconfig.train.envから抜いたりしないこと。** ただし前提として
  GitHub上のリポジトリ(`taniguchitakara/so101-aist`)がPrivateであることに依存しているため、
  リポジトリをPublicにする/コラボレーターを追加する話が出た場合は、先にwandb側で
  APIキーを再発行してconfig.train.envを更新するようユーザーに念押しすること
  （Gitの履歴に平文で残るため、ファイルを書き換えるだけでは無効化されない）。

## ユーザーの目的

ユーザーの主目的は、自分で教示データを集めて学習することではなく、
**既存/学習済みポリシー（openpi・pi0系、LeRobotネイティブのpi0サポート経由）をフォロワーアーム単体で
推論実行させること**（`lerobot-rollout`、`02_train/09_rollout_inference.sh`）。
リーダーアームのモーター設定・キャリブレーションは一応済ませてあるが、この目的には必須ではない
（teleoperationでの自作データ収集をする時だけ必要になる）。

## モーターID設定まわりの安全策（触るときは要注意）

過去に、既にモーターID設定が済んだ状態で`00_setup/02_setup_motors_leader.sh`をうっかり再実行し、
ID 1（shoulder_pan）とID 6（gripper）が壊れる事故が起きた。これを受けて以下を追加済み:

- `tools/check_motors_configured.py`: 6個のモーター全部に個別pingを送り、既に正しいIDで応答するか確認するツール
  （IDが重複していれば個別pingには正しく応答できないので、切り離さずに安全にチェックできる）。
- `00_setup/02_setup_motors_follower.sh` / `00_setup/02_setup_motors_leader.sh` は`config.common.env`読み込み直後にこのチェックを実行し、
  既に6個全部が応答していたら警告を出し、`yes`と入力しない限り`lerobot-setup-motors`の実行を中止する
  （`read -p` + `exit 1`）。**この安全策はユーザーからの明示的な要望で入れたものなので、
  正当な理由なく削除・弱体化しないこと。**
- `tools/fix_motor_id.py` / `tools/fix_motor_id.sh`: 1個だけ壊れたモーターIDを、6個全部やり直さずに直すツール
  （`./tools/fix_motor_id.sh <follower|leader> <motor_name>`）。`MotorsBus.setup_motor(name)`を直接呼んでいる。

これらの詳細はREADME.mdの「モーターIDのトラブル対応」セクションにも書いてある。

## Linuxマシン（実機側）の環境情報

実際に学習・推論・実機操作が走っているLinuxマシン自体には、このセッションのdevice_bashは
到達できない（Macにしか繋がっていない）。そのため、そのマシンのハードウェア/ドライバ/ライブラリ
構成はユーザーから聞いた情報を都度ここに書き足していく方針（ユーザー2026-09-01指示：「linuxマシン
情報は随時Agents.mdに書いといて」）。新しい情報が分かるたびに追記し、GPU/CUDA/ドライバ周りの
トラブルシュートで真っ先に参照すること。

- NVIDIAドライバのCUDAサポートバージョン: **12.6**（`nvidia-smi`表示の「CUDA Version」）。
- 2026-09-01時点で判明したトラブル: `.venv`にインストールされたPyTorchがCUDA **13**系向けビルドで、
  ドライバの12.6と不整合 → `torch.cuda.is_available()`が`False`になり、学習が黙ってCPUにフォールバック
  していた（`POLICY_DEVICE=auto`が`nvidia-smi`ベース判定だった旧版では「自動判定結果: cuda」と表示されるのに
  実際の`lerobot-train`はCPUで走る、という食い違いが発生）。
  対処: `uv pip install --python .venv --reinstall-package torch torch --torch-backend=cu126` でドライバに
  合うCUDA 12.6版torchに入れ直す（`--torch-backend`はuvの機能）。ドライバをCUDA13対応版へ上げる方法もあるが、
  再起動や他プロセスへの影響があるためtorch側を合わせる方を優先した。

## ファイル一覧の前提

`00_setup/00_install.sh` 〜 `02_train/13_train_policy_groot_multi_gpu.sh`（番号順に実行する想定。ただし13番は11番の
マルチGPU版なので11番の代わりに使うもので、11→13→12の順ではなく11か13のどちらかを実行してから12番、
という位置づけ）、`config.common.env`/`config.collect.env`/`config.train.env`（環境ごとの
設定値。wandb APIキーを含む点に注意 — 上記参照）、`README.md`、`tools/fix_motor_id.py`/`.sh`、
`tools/check_motors_configured.py`、`tools/fix_dataset_tag.py`/`.sh`、`tools/checkpoint_hub_gc.py`/`.sh`
（学習チェックポイントのHub専用化ツール）。全てのコメント・READMEは日本語
（ユーザーが日本語での作業を希望しているため）。
