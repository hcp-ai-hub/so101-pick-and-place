# test/ : NVIDIA公式リポジトリで「素の (ファインチューニング前の) GR00T-N1.7-3B」を実機で動かすテスト

`../00_setup/10_install_groot.sh`〜`../02_train/12_rollout_inference_groot.sh`（LeRobotにネイティブ統合されたGR00T）とは別物です。
そちらは`--policy.path`にLeRobot形式のチェックポイントを要求するため、`nvidia/GR00T-N1.7-3B`をファイン
チューニングせずそのまま渡すと `Could not instantiate class RolloutConfig using the given arguments`
のようなエラーになりました（LeRobotの保存形式とNVIDIA配布の生チェックポイントの`config.json`の形が違うため）。

ここでは代わりに **NVIDIA公式の [Isaac-GR00T](https://github.com/NVIDIA/Isaac-GR00T) リポジトリ自身の
Policy API / SO-100評価サンプル** を使い、ファインチューニングしていない `nvidia/GR00T-N1.7-3B` を
そのまま実機のSO-101で動かしてみるテストです。Isaac-GR00T側の`Gr00tPolicy`はNVIDIA配布の生の
チェックポイントをそのままロードできる作りなので、こちらなら「ロードすらできない」問題は起きません。

参考: [examples/SO100/README.md](https://github.com/NVIDIA/Isaac-GR00T/blob/main/examples/SO100/README.md)

## 期待値（重要）

**タスクをこなせるとは期待しないでください。** `--embodiment-tag NEW_EMBODIMENT` は「GR00Tが事前学習で
見たことのない新しいロボット構成」を表すタグで、この構成向けの行動出力部分（action head）はファイン
チューニングして初めて意味を持ちます。ファインチューニング無しで動かすと、ロードや推論ループ自体は
最後まで回るはずですが、出てくる動作はSO-101のタスクとは無関係の、ほぼランダムに近いものになる
可能性が高いです。これは「パイプラインが最後まで動くか」を確認するテストであって、「GR00Tが既に
このタスクをできるか」のテストではありません。

## このテストだけの特別な条件

- **カメラは `front` + `wrist` の2台が必須**です。公式の`so100_config.py`が
  `modality_keys=["front", "wrist"]` と両方をハードコードしているため、現在の本線（`../config.common.env`）の
  front1台構成のままではこのテストは動きません。一時的にwristカメラを繋ぎ直してください
  （`../docs/CAMERA_SETUP.md` 参照）。
- **GPU VRAM 16GB以上が推論だけでも必要**（NVIDIA公式README記載の最低ライン）。学習(fine-tune)は
  さらに40GB以上必要ですが、今回は学習しないのでこちらの基準で足ります。
- **Hugging Faceの認証が必要**: VLMバックボーンがgatedなモデルのため、事前に
  `huggingface-cli login` するか `HF_TOKEN` 環境変数を設定してください。
- Isaac-GR00Tリポジトリは**独自の`.venv`**を持ちます（`so101-aist`本体の`.venv`とは別物）。混ざらない
  ようにこの`test/`フォルダの中に`Isaac-GR00T`をcloneします。

## 実行順序

| # | スクリプト | 内容 |
|---|-----------|------|
| 0 | `00_setup_isaac_groot.sh` | Isaac-GR00T リポジトリを `test/Isaac-GR00T` に clone し、`uv sync` で依存関係をインストール |
| 1 | `01_setup_client.sh` | SO-100実機評価クライアント側の依存関係をセットアップ（別の`.venv`） |
| 2 | `02_start_groot_server.sh` | GR00Tポリシーサーバーを起動（**別ターミナルで実行し、起動したままにしておく**） |
| 3 | `03_run_pretrained_rollout.sh` | クライアント側からロボットを動かす（サーバーを起動した状態で実行） |

`02`は起動したままにしておく必要があるので、`03`を実行するときは別のターミナル（別のタブ/セッション）
を開いてください。

## 安全上の注意

ファインチューニングしていない出力で腕を動かすので、**予測不能な動きをする前提で臨んでください**。

- 周囲に物・人がいない状態で実行する
- いつでも電源を落とせる位置に立つ
- まず短時間（`03_run_pretrained_rollout.sh`のタイムアウトを短く）で試す
- 想定外の動きをしたら即座に電源を切る

## 参考リンク

- [examples/SO100/README.md](https://github.com/NVIDIA/Isaac-GR00T/blob/main/examples/SO100/README.md)
- [NVIDIA/Isaac-GR00T (本体)](https://github.com/NVIDIA/Isaac-GR00T)
- [gr00t/eval/real_robot/SO100/eval_so100.py](https://github.com/NVIDIA/Isaac-GR00T/blob/main/gr00t/eval/real_robot/SO100/eval_so100.py)
- [examples/SO100/so100_config.py](https://github.com/NVIDIA/Isaac-GR00T/blob/main/examples/SO100/so100_config.py)
