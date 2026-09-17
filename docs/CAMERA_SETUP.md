# カメラ・実環境セットアップガイド（GR00T N1.7向け）

`02_train/08_train_policy.sh`/`02_train/09_rollout_inference.sh`（ACT / pi0系）に加えて、GR00T N1.7（`10`〜`12`番のスクリプト）を実機で動かすために必要な、カメラと実環境のセットアップをまとめたドキュメントです。

## 推奨カメラ構成: front（正面/俯瞰）+ wrist（手首）の2台

NVIDIA公式のGR00T N1.7 × LeRobot × SO-101の実行例では、以下の2カメラ構成が使われています。

| カメラ | 役割 | 設置場所 |
|---|---|---|
| `front` | 作業スペース全体・対象物の位置・アーム全体の動きを捉える | フォロワーアームの正面〜斜め上、作業台全体が入る位置に固定（具体的な高さ・距離は次項参照） |
| `wrist` | グリッパー付近の接触・把持の瞬間を捉える | フォロワーアームの手首（グリッパーの付け根付近）に取り付け |

### `front` カメラの具体的な位置

NVIDIA公式ブログ（GR00T N1.7 × LeRobot × SO-101）や LeRobot 本体のドキュメントには、`front` カメラの正確な設置距離・高さ・角度までは明記されていません（"front" という名前と設定例があるだけです）。そのためここでは、他の実践報告から得られる目安を示します。

- **アームの正面〜斜め前方**に置き、**作業台の上（対象物が置かれる範囲＋グリッパーの可動範囲全体）が画角に収まる**距離・高さに調整する。目安として、卓上タスクなら**アームの付け根から40〜60cm程度離し、テーブル面からやや見下ろす高さ**に置くケースが多いです。
- 真横からではなく、**正面〜やや上から**にすると、グリップ時に指先同士が重なって見えなくなる「オクルージョン（隠れ）」が起きにくいという報告があります（ACTでSO-101を学習した際の実践記録: 真横カメラは掴む瞬間に指先が重なって使い物にならず、正面+上からの構図に変えて改善したとのこと）。
- アーム本体がカメラと作業台の間に入り込んで視界を遮らない位置を選ぶ。

### GR00Tの事前学習済みモデル（ベースモデル）を使う場合、位置合わせは必要？

結論: **GR00T-N1.7-3Bの事前学習時のカメラ位置に厳密に合わせる必要はありません。**

`02_train/11_train_policy_groot.sh` は `--policy.embodiment_tag=new_embodiment` を指定してファインチューニングします。これは「これはGR00Tが事前学習で見たことのない新しいロボット/カメラ構成です」とモデルに伝える仕組みで、この構成のもとでは自分たちのSO-101・カメラ配置に合わせて追加学習することが前提になっています。つまり、事前学習データの撮影アングルを再現しようとする必要はありません。

ただし、以下は依然として重要です（ベースモデルの視覚バックボーンが一般的な画像で事前学習されているため、極端なアングルより「人が見るような自然な構図」の方が転移しやすいと考えられます）。

- 上記の `front` カメラの目安（正面〜斜め上、作業台全体が入る、極端な魚眼/真上/真横を避ける）に沿わせる
- 収録時と推論時でカメラの位置・角度を**物理的に絶対に動かさない**（テープや印で位置をマーキングしておくと安全）
- 実は「SO-101のカメラ配置に唯一の正解があるか」はLeRobotコミュニティでも[まだ明確な答えが出ていない話題](https://github.com/huggingface/lerobot/issues/1763)です。迷ったら、まず一般的な目安で決めてしまい、そこから動かさない運用を徹底する方が、正解を探すよりも重要です。

この2台構成が推奨される理由:

- **frontだけ**: 全体の状況は分かるが、グリッパー周辺の細かい様子（物を掴めているか等）が見えにくい。
- **wristだけ**: 把持の瞬間には強いが、手首が動くたびに視点が変わってしまい、物体がどこにあるかという大域的な情報が失われる。
- **front + wrist**: 大域的な文脈と局所的な把持ディテールの両方が得られる。その分USB帯域・保存容量・処理負荷は増える。

## config.common.env での設定

`config.common.env` の `CAMERA_CONFIG` は辞書形式で複数台を指定できます。2台のUSB Webカメラを同時に使う場合、帯域を抑えるために `fourcc: MJPG` を指定するのがポイントです（公式例もMJPG指定）。

```bash
export CAMERA_CONFIG='{ front: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 30, fourcc: MJPG}, wrist: {type: opencv, index_or_path: 2, width: 640, height: 480, fps: 30, fourcc: MJPG} }'
```

- `index_or_path` は実際の環境で変わります。`lerobot-find-cameras opencv` を実行して調べたデバイス番号に書き換えてください。
- RealSenseカメラを使う場合は `type: intelrealsense`、`index_or_path` の代わりに `serial_number_or_name` を使います。

## USBの物理的な繋ぎ方

### front（固定）カメラ
- 三脚やクランプで固定した位置から、そのまま計算機（LeRobotのスクリプトを実行しているLinux機）のUSBポートに挿すだけでOKです。動かないカメラなので特別な配線の工夫は不要です。
- 可能なら USB3 (青色のポート) に挿してください。解像度・fpsを上げたい場合に帯域の余裕が出ます。

### wrist（手首）カメラ
- グリッパー付近に固定します（3Dプリントのマウントを使う例が多いです。例: [SO-ARM101 Wrist Camera Mount](https://www.juxitech.com/products/so-arm101-wrist-camera-mount)、[MakerWorldのマウント例](https://makerworld.com/en/models/2445589-camera-module-mount-for-so-101-robot-arm)）。
- USBケーブルは手首が可動域いっぱいに回転・屈曲しても**ケーブルが突っ張ったり引っかかったりしない長さの余裕（たるみ）**を持たせて、アームの各リンクに沿わせながら結束バンドやスパイラルチューブで固定してください。
- 配線したら、**電源を入れずに手動でアームの関節を可動域いっぱいまで動かしてみて**、ケーブルが突っ張らないか・他の配線に絡まないかを確認してから通電してください（NVIDIA公式ガイドも「ケーブルは動作中に引っかからないよう配線を確認する」ことを明記しています）。
- 既製の手首カメラモジュール（例: [WowRobo 2MP USB Camera Module](https://shop.wowrobo.com/products/2mp-usb-camera-module-for-so-arm100-101-30fps-3m-cable), 3mケーブル付き）を使うと、可動域分の長さが最初から確保しやすいです。

### 2台をどのUSBポート/ハブに挿すか
- フォロワー/リーダーアームのモーターバス変換器（`/dev/ttyACM*`）はシリアル通信で帯域をほぼ使わないので、同じハブに挿しても基本問題ありません。
- 一方、**Webカメラ2台は帯域とアイソクロナス転送を食うため、できれば計算機の別々のUSBポート（可能なら別のUSBコントローラ）に直接挿してください**。同じUSBハブ1つに2台とも挿すと帯域不足でタイムアウトしやすくなります。
- どうしてもハブ経由にする場合は、バスパワーの安いハブではなく**セルフパワー（ACアダプタ付き）のUSB3ハブ**を使ってください。カメラ2台分の電力・帯域を安定して確保できます。
- カメラを挿し直す・PCを再起動すると `index_or_path` の番号がズレることがあります。挿し直した後は必ず `lerobot-find-cameras opencv` を実行し直して、`config.common.env` の `CAMERA_CONFIG` の番号が今も合っているか確認してください。

### 実機トラブル事例（2026-09-07）: RealSense併用時にwristカメラがtimeoutする

**症状**: wristカメラ（innomaker製 USB2.0 UVCカメラ）だけを繋いでいる時は安定して動くのに、Intel RealSenseカメラも同時に接続すると `TimeoutError: Timed out waiting for frame` が発生する。RealSenseとwristカメラを**物理的に別々のUSBポート**に挿し直しても症状は変わらなかった。

**診断方法**: `lsusb -t` でUSBツリー全体を確認したところ、以下が判明した。

- RealSense（Video interfaceが5つ＋HID 1つという構成から判別: color/depth/IR/モーションモジュール）が、USB3の高速バス（Bus 02, 5000M/20000M）ではなく、**USB2側のBus 01（480M）にフォールバックして繋がっていた**。Bus 02側にはHubクラスのデバイスしかなく、カメラは1台も載っていなかった。
- wristカメラ（innomaker, Video interfaceが2つ）も同じBus 01の中の、共通の上流ハブ配下にぶら下がっていた（さらにロボットアーム2本のシリアル制御 `cdc_acm` も同じ階層を共有）。
- つまり「別々のポートに挿した」つもりでも、内部的には同じUSB2の480Mbps帯域を、RealSense・wristカメラ・アーム制御が全部で奪い合っていた。RealSenseは本来USB3(5Gbps級)前提で帯域を大きく使うデバイスなので、480Mbpsの共有バスに押し込まれると他のUVCデバイスを簡単に圧迫する。

**対策**:
1. RealSenseのケーブルを、PCの青色（USB3/SS）ポートに直挿しする。今使っている配線（ケーブル自体 or 経由しているハブ）がUSB2止まりになっている可能性が高い。
2. 挿し直した後に `lsusb -t` を再実行し、RealSenseがBus 02側（5000M）に載っていることを確認する。ここがまだ480Mのままなら、ケーブルかハブがUSB2専用の可能性が高いので交換する。
3. RealSenseが正しくUSB3で繋がれば、wristカメラ・アーム制御が使っているUSB2バスの帯域を圧迫しなくなり、timeoutが解消するはず。

参考: RealSense公式ドキュメントは「D400シリーズはUSB3.0 (5000Mbps) で900mA/4.5W給電のポート前提、実際は最大2W/台消費するため外部給電ハブ推奨」「1台のD415で1280x720 depth+color@30fpsが約1105Mbps消費する」と明記しており、USB2(480Mbps)には収まらない帯域であることが裏付けられる（[RealSense Multi-Camera configurations](https://dev.realsenseai.com/docs/multiple-depth-cameras-configuration/)）。同様の「RealSense+別UVCデバイスの同時使用でdisconnectする」報告はNVIDIA Jetson環境でも見られる（[NVIDIA Developer Forums](https://forums.developer.nvidia.com/t/realsense-d435-and-additional-uvc-device-usb-disconnections-on-jetson-orin-nx-three-scenarios-with-tegra-xusb-errors-emi-and-potential-hub-resets/342718)）。

なお、これまでの調査過程で「wristカメラ本体（innomaker USB2.0_CAM1, Sonixチップ）が故障している」という仮説が有力視されていたが、RealSenseを抜くとwristカメラが安定して動いたことから、**この仮説は誤りだった可能性が高い**。真因はRealSenseのUSB2フォールバックによる帯域競合と見られる。wristカメラの交換は保留し、まずRealSenseをUSB3で正しく認識させる対策を優先する。

### 追記（2026-09-07 続報）: RealSenseケーブル交換後、今度は front/wrist 両方で別のパス(/dev/video0)がtimeout

Amazon Basics製のRealSense用Type-C to Type-Aケーブルが怪しいと判断し交換を試みた後、`01_collect/06_record_dataset.sh` を実行したところ、以下のログが出た。

```
INFO  OpenCVCamera(/dev/video6) connected.
WARN  tryIoctl VIDEOIO(V4L2:/dev/video0): select() timeout.
WARN  Error reading frame ... OpenCVCamera(/dev/video0) read failed (status=False).
WARN  tryIoctl VIDEOIO(V4L2:/dev/video6): select() timeout.
WARN  Error reading frame ... OpenCVCamera(/dev/video6) read failed (status=False).
...
TimeoutError: Timed out waiting for frame from camera OpenCVCamera(/dev/video0) after 10000 ms. Read thread alive: True.
```

**重要な点**: この時点の `config.env` の `CAMERA_CONFIG` は `front=/dev/video6`, `wrist=/dev/video2` だったが、エラーに出てくるのは `/dev/video0` と `/dev/video6` であり、`/dev/video2` はログに一切登場しない。

**考えられる原因**: RealSenseのUSBケーブルを挿し直した際に、Linuxが `/dev/videoN` の番号を検出順で振り直した可能性が高い。特にRealSenseは1台でcolor/depth/IR用に複数の `/dev/videoN` を専有するため、RealSenseの抜き差しは他のUSB webcamの番号にも影響しやすい。つまりこの失敗は、以前の物理的なUSB切断とは別に、**config.envが古い（今は別の機器を指している）デバイスパスを参照しているだけ**の可能性がある。

**次にやること（未実施）**:
1. `lerobot-find-cameras opencv` を再実行し、front/wristの実際の `/dev/videoN` を確認する。
2. `lsusb -t` を再実行し、ケーブル交換でRealSenseがBus02（USB3, 5000M以上）に載るようになったか確認する。
3. 上記2点の結果を見て、config.envの `CAMERA_CONFIG` のパスを実機の現状に合わせて修正する。

**再現確認（2026-09-07 同日再実行）**: 同じ `01_collect/06_record_dataset.sh` をもう一度実行したところ、今回は `/dev/video6` は最後まで問題なく動作し、`/dev/video0` だけが同じ `TimeoutError`（10000ms）で失敗した。つまり `/dev/video0` は一時的な不調ではなく、**再現性のある問題**として固定されている。前回video6も一瞬timeoutしていたのは恐らく起動直後の一過性のものだった可能性がある。

`lerobot-find-cameras opencv` と `lsusb -t` の出力はまだ受け取っていない。この2つが無いと、`/dev/video0` が実際には何（front/wrist用の物理webcamなのか、RealSenseが専有している内部streamノードなのか、あるいはconfig.envが単に古いパスを指しているだけなのか）を指しているのか判別できないため、次のアクションはまだ保留。

**判明（2026-09-07 続報3）**: `/dev/video0` の正体はユーザーに確認したところRealSenseだった。つまり `config.env`（少なくとも実機側の現行版）は front または wrist のどちらかで **RealSenseを `type: opencv`（生のV4L2アクセス）として設定してしまっていた**。RealSenseはcolor/depth/IRを同期して扱う専用デバイスで、露光やフォーマット制御を`librealsense`経由で行う前提のため、`cv2.VideoCapture`による素朴な読み取りでは映像が返らず`TimeoutError`になる。正しくは LeRobot側の専用カメラタイプ `type: intelrealsense`（`index_or_path`の代わりに`serial_number_or_name`を使う）を使う必要がある。

**しかし** `lerobot-find-cameras realsense` を実行すると `Error finding RealSense cameras: 'NoneType' object has no attribute 'context'` → `No realsense cameras were detected.` というエラーになり、シリアル番号を取得できない状態。原因切り分けのため`lsusb -t`を2回連続取得したところ:

- 1回目: RealSenseがツリーから完全に消えていた（Bus01/Bus02どちらにも存在しない＝物理的に認識されていなかった）。
- 2回目（挿し直し後）: RealSense（`Dev 102`、Video interface×5 + HID×1、以前の`Dev 87`と同じ特徴）が再びツリーに登場したが、**依然としてBus 01（USB2, 480M）側**だった。以前は`root→Dev2→Dev76→Dev87`と1段余分にハブを挟んでいたが、今回は`root→Dev2→Dev102`と1段浅い（＝挿すポートを変えた可能性がある）ものの、Bus02（USB3, 5000M以上）には変わらず載っていない。

**結論（暫定、2026-09-07時点）**: Amazon BasicsのType-C to Type-Aケーブルを交換した後も、RealSenseはUSB3（SuperSpeed）として認識されていない。挿すポートを変えても480Mのままなので、交換後のケーブル自体、またはRealSense側のUSB-Cポートが依然としてSuperSpeedレーンを確立できていない可能性が高い。`lerobot-find-cameras realsense`のエラーは、librealsenseの実装バグというより、そもそも実効的なRealSenseデバイスとして（十分な帯域で）認識されていないことの副次的な症状である可能性がある。

**次にやること（未実施）**:
1. `dmesg -T | tail -30` を、RealSenseを抜き差しした直後に確認し、`new SuperSpeed USB device` と `new high-speed USB device` のどちらが出るか直接確認する。
2. 交換したケーブルのパッケージ/本体に「SuperSpeed」「USB 3.x」「5Gbps」等の表記が本当にあるか再確認する。無ければそのケーブルもUSB2止まりの可能性が高い。
3. 可能であれば、RealSense購入時に同梱されていた純正ケーブルを探して試す（最も確実な切り分け）。
4. `rs-enumerate-devices`（librealsense SDKのCLI、入っていなければ command not found になるはず）や、venv内で `python3 -c "import pyrealsense2 as rs; print(rs.context().query_devices())"` を実行し、lerobot側のバグなのか、そもそもUSBレベル/librealsenseレベルで認識されていないだけなのかを切り分ける（まだ未実施）。
5. RealSenseがUSB3で正しく認識されてシリアル番号が取得できたら、`config.env`の該当エントリを `type: intelrealsense, serial_number_or_name: <シリアル番号>` に書き換える（`index_or_path`ではない点に注意）。

なお、innomaker（wristカメラ、`Dev 99`）は今回も安定して認識されている。問題はRealSense側のUSB3接続確立、および正しいカメラタイプでの設定に絞られてきている。



## 動作確認の手順（重要: 一気に2台つながない）

1. **1台ずつ確認する**: まずカメラ1台だけ接続し、`lerobot-find-cameras opencv` で認識されるか確認する。
2. **単体で映像確認**: `00_setup/05_teleoperate_with_camera.sh` の `CAMERA_CONFIG` を一時的に1台構成にして、`--display_data=true` の映像ウィンドウで正しく映るか確認する。
3. **2台同時接続**: 問題なければ2台目を接続し、`config.common.env` の `CAMERA_CONFIG` を上記のfront+wrist構成に戻して再度 `00_setup/05_teleoperate_with_camera.sh` で確認する。
4. **タイムアウトが出る場合**: 2台同時だとUSB帯域不足で映像取得がタイムアウトすることがあります。以下を試してください。
   - 解像度・fpsを下げる（例: 640x480→480x360、fps 30→15）
   - 2台のカメラを**別々のUSBコントローラ/ハブ**に挿す（同じハブに集中させない）
   - 他のアプリ（Zoom、ブラウザのカメラ機能等）がカメラを掴んでいないか確認する

## GR00T特有の注意点: レストポーズ（開始姿勢）を収録時と揃える

NVIDIA公式ガイドが明記している重要な注意点です。

> ロボットの開始姿勢（レストポーズ）は、データ収録時と推論（rollout）時で必ず揃えてください。例えば腕が縮こまった（crouch）姿勢のままだと、カメラが作業台を十分に写せず、ポリシーがタスクを認識できないことがあります。

つまり:

- `01_collect/06_record_dataset.sh` で収録を始める前のロボットの初期姿勢・カメラの視野を、`02_train/12_rollout_inference_groot.sh` で推論を始める前の姿勢・視野と一致させる。
- カメラの位置・角度自体も、収録から推論まで**物理的に動かさず固定**する（三脚やクランプで固定し、途中でズレないようにする）。
- 毎エピソード開始位置がバラバラだと学習・推論の両方で精度が落ちるので、`00_setup/04_teleoperate.sh` 等で「開始姿勢」を決めておき、収録の度になるべく同じ位置に戻すことを意識する。

## チェックリスト

- [ ] `lerobot-find-cameras opencv` で front / wrist 両方のカメラが認識されている
- [ ] `config.common.env` の `CAMERA_CONFIG` に front / wrist 両方の設定が書かれている（`fourcc: MJPG` 込み）
- [ ] `00_setup/05_teleoperate_with_camera.sh` で2台同時の映像がタイムアウトなく表示される
- [ ] カメラが三脚・クランプ等で物理的に固定されている
- [ ] ロボットの開始姿勢を決めて、収録・推論で毎回同じ位置に戻すようにしている

## 参考リンク

- [NVIDIA Isaac Teleop and GR00T 1.7 Open VLA Model Available in LeRobot](https://huggingface.co/blog/nvidia/nvidia-isaac-teleop-and-gr00t17-in-lerobot)
- [Post-Training Isaac GR00T N1.5 for LeRobot SO-101 Arm](https://huggingface.co/blog/nvidia/gr00t-n1-5-so101-tuning)
- [LeRobot Cameras documentation](https://huggingface.co/docs/lerobot/cameras)
- [LeRobot SO-101 Setup: Calibration, Cameras and Teleoperation – OpenELAB](https://openelab.io/blogs/learn/lerobot-so101-setup-calibration-cameras-teleoperation)
