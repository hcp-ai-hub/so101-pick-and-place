#!/usr/bin/env python3
"""
fix_dataset_tag.py : HF Hub上のデータセットリポジトリに codebase_version の
                      git tag が無いときに、後から付け直すツール

なぜ必要か:
  lerobot-record は収録後、通常 LeRobotDataset.push_to_hub() を呼び、
  アップロードに加えて「codebase_version（例: v3.0）」という名前の
  git tag をHub上のデータセットリポジトリに自動で作成します。
  lerobot-train や lerobot-rollout がHubからデータセットを読み込むとき、
  この tag（または同じメジャーバージョンのtag）が無いと

    RevisionNotFoundError: Your dataset must be tagged with a codebase version.

  というエラーになります。

  06_record_dataset.sh の実行中に何らかの理由でアップロードが失敗し
  （プライベートリポジトリの認証エラー等）、代わりにスクリプトが案内する
  手動コマンド「hf upload <repo_id> <local_dir> --repo-type dataset」で
  アップロードし直した場合、この `hf upload` はファイルを置くだけで
  tag は作成しないため、上記のエラーになります。このスクリプトはその
  tag 付けだけを後から行います。

使い方:
  # config.common.env の DATASET_REPO_ID に対して実行（ローカルキャッシュの
  # meta/info.json から codebase_version を自動で読み取ります）
  python fix_dataset_tag.py --repo-id taniguchitakara/so101_test_dataset

  # ローカルにキャッシュが無い/バージョンを明示したい場合
  python fix_dataset_tag.py --repo-id taniguchitakara/so101_test_dataset --version v3.0

実行後、`lerobot-train --dataset.repo_id=...` 等が再びHubから読み込める
ようになります（tagは既存があれば一旦消してから作り直すので、
何度実行しても安全です）。
"""

import argparse
import json
import os
from pathlib import Path


def local_dataset_dir(repo_id: str) -> Path:
    # lerobot/utils/constants.py の HF_LEROBOT_HOME と同じロジック
    # (デフォルト: $HF_HOME/lerobot, HF_HOME未設定なら ~/.cache/huggingface)
    from huggingface_hub.constants import HF_HOME

    default_cache_path = Path(HF_HOME) / "lerobot"
    home = Path(os.getenv("HF_LEROBOT_HOME", default_cache_path)).expanduser()
    return home / repo_id


def detect_local_codebase_version(repo_id: str) -> str | None:
    info_path = local_dataset_dir(repo_id) / "meta" / "info.json"
    if not info_path.exists():
        return None
    with open(info_path) as f:
        info = json.load(f)
    return info.get("codebase_version")


def main():
    parser = argparse.ArgumentParser(description="HF Hub上のデータセットに codebase_version tag を付け直す")
    parser.add_argument("--repo-id", required=True, help="例: taniguchitakara/so101_test_dataset")
    parser.add_argument(
        "--version",
        default=None,
        help="付けるtag名（例: v3.0）。省略時はローカルキャッシュの meta/info.json から自動検出します。",
    )
    parser.add_argument(
        "--revision",
        default="main",
        help="どのブランチ/コミットにtagを打つか（既定: main）",
    )
    args = parser.parse_args()

    version = args.version or detect_local_codebase_version(args.repo_id)
    if version is None:
        # ローカルにもキャッシュが無い場合、インストール済みlerobotの
        # 現在のcodebase versionを最後の手段として使う
        try:
            from lerobot.datasets.lerobot_dataset import CODEBASE_VERSION

            version = CODEBASE_VERSION
            print(
                f"ローカルキャッシュの meta/info.json が見つからなかったため、"
                f"インストール済みlerobotの現在のバージョン ({version}) を使います。"
            )
        except ImportError:
            parser.error(
                "codebase_versionを自動検出できませんでした。"
                "--version=v3.0 のように明示的に指定してください"
                "（Hub上のリポジトリの meta/info.json を確認すると正確な値が分かります）。"
            )

    print(f"repo_id   : {args.repo_id}")
    print(f"tag       : {version}")
    print(f"revision  : {args.revision}")

    from huggingface_hub import HfApi
    from huggingface_hub.utils import RevisionNotFoundError

    hub_api = HfApi()

    try:
        hub_api.delete_tag(args.repo_id, tag=version, repo_type="dataset")
        print(f"既存の tag={version} を削除しました（作り直します）。")
    except RevisionNotFoundError:
        pass

    hub_api.create_tag(args.repo_id, tag=version, revision=args.revision, repo_type="dataset")
    print(f"tag={version} を作成しました。lerobot-train / lerobot-rollout から再度読み込めるはずです。")


if __name__ == "__main__":
    main()
