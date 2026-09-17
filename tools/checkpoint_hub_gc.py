#!/usr/bin/env python3
"""
checkpoint_hub_gc.py : Hubへのアップロードが確認できたローカルのチェックポイントを
                        自動削除し、チェックポイントを実質的に「リモート(Hub)のみ」に
                        保つためのツール

背景:
  lerobot-train は `--save_checkpoint_to_hub=true` のとき、各チェックポイントを
  ローカル(`output_dir/checkpoints/<step>/`)に保存した直後・同一プロセス内で
  同期的にHubへアップロードし、アップロードした内容と同じ名前(ステップ番号)の
  git tag をHub上のモデルリポジトリ(`--policy.repo_id`)に作成します
  (`lerobot.common.train_utils.push_checkpoint_to_hub`)。

  つまり「ローカルにそのステップ番号のディレクトリがある」かつ「Hub上に同名の
  tagがある」なら、そのチェックポイントは確実にHubへのアップロードが完了済みです。
  このスクリプトはその2つを突き合わせ、Hub側にtagが存在するローカルディレクトリ
  だけを安全に削除します（アップロードが未確認のものには一切触れません）。

  lerobot-train 自体には「ローカルに書かずに直接Hubへ」という機能は無いため、
  これは学習プロセスの外から並行して動かす補助スクリプトです。

注意 (再開について):
  このスクリプトで削除したチェックポイントは、ローカルの
  `checkpoints/last/pretrained_model/train_config.json` 経由では再開できません
  （ファイル自体が無くなるため）。`--save_checkpoint_to_hub=true` で学習した
  run を再開するときは、Hub上のリポジトリを直接指定してください:

    lerobot-train --config_path=<HF_USER>/<policy_repo> --resume=true

  (lerobot-train は resume=true のとき、config_path に Hub の repo_id を渡すと
   最新のチェックポイントを自動でダウンロードして再開します。)

使い方:
  # 学習と並行してバックグラウンドでポーリング（08/11番スクリプトから自動起動されます）
  python checkpoint_hub_gc.py --output-dir outputs/train/groot_so101 \\
      --repo-id taniguchitakara/my_so101_groot_policy --interval 60

  # 1回だけ実行して終了（学習終了後の仕上げ、または手動クリーンアップ用）
  python checkpoint_hub_gc.py --output-dir outputs/train/groot_so101 \\
      --repo-id taniguchitakara/my_so101_groot_policy --once
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
import time
from pathlib import Path

from huggingface_hub import HfApi
from huggingface_hub.utils import RepositoryNotFoundError

STEP_DIR_RE = re.compile(r"^\d+$")


def get_uploaded_steps(api: HfApi, repo_id: str) -> set[str]:
    """Hub上のモデルリポジトリに存在するtag名（=アップロード済みステップ）の集合を返す。

    リポジトリがまだ存在しない場合（最初のチェックポイントより前など）は空集合を返す。
    """
    try:
        refs = api.list_repo_refs(repo_id=repo_id, repo_type="model")
    except RepositoryNotFoundError:
        return set()
    return {tag.name for tag in refs.tags}


def clean_once(output_dir: Path, repo_id: str, api: HfApi, keep_last_n: int = 0) -> int:
    """1回分のクリーンアップを実行し、削除した件数を返す。"""
    checkpoints_dir = output_dir / "checkpoints"
    if not checkpoints_dir.is_dir():
        return 0

    local_steps = sorted(
        (p for p in checkpoints_dir.iterdir() if p.is_dir() and STEP_DIR_RE.match(p.name)),
        key=lambda p: int(p.name),
    )
    if not local_steps:
        return 0

    uploaded = get_uploaded_steps(api, repo_id)
    # keep_last_n > 0 の場合、アップロード確認済みでも直近N個はローカルに残す
    # （デフォルトは0 = すべて削除。「リモートのみ」にするための既定値）
    candidates = local_steps[: len(local_steps) - keep_last_n] if keep_last_n > 0 else local_steps

    removed = 0
    for step_dir in candidates:
        if step_dir.name not in uploaded:
            continue  # Hubへのアップロード未確認 → 触らない
        shutil.rmtree(step_dir, ignore_errors=True)
        print(f"[checkpoint_hub_gc] Hubへのアップロードを確認 -> ローカル削除: {step_dir}", flush=True)
        removed += 1

    # `last` シンボリックリンクの参照先を削除した場合、リンク自体も掃除しておく
    # （壊れたシンボリックリンクが残らないようにするだけで、実害はない）
    last_link = checkpoints_dir / "last"
    if last_link.is_symlink() and not last_link.resolve().exists():
        last_link.unlink(missing_ok=True)

    return removed


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Hubへのアップロードが確認できたローカルのチェックポイントを自動削除する",
    )
    parser.add_argument("--output-dir", required=True, type=Path, help="lerobot-train の --output_dir")
    parser.add_argument("--repo-id", required=True, help="lerobot-train の --policy.repo_id")
    parser.add_argument("--interval", type=float, default=60.0, help="ポーリング間隔（秒、デフォルト60）")
    parser.add_argument("--once", action="store_true", help="ループせず1回だけ実行して終了する")
    parser.add_argument(
        "--keep-last-n",
        type=int,
        default=0,
        help="アップロード確認済みでも直近N個はローカルに残す（デフォルト0=すべて削除）",
    )
    args = parser.parse_args()

    api = HfApi()

    if args.once:
        removed = clean_once(args.output_dir, args.repo_id, api, args.keep_last_n)
        print(f"[checkpoint_hub_gc] 完了: {removed}件削除")
        return

    print(
        f"[checkpoint_hub_gc] 監視開始: {args.output_dir}/checkpoints "
        f"(repo={args.repo_id}, interval={args.interval}s) — Ctrl+C または親プロセス終了で停止します",
        flush=True,
    )
    while True:
        try:
            clean_once(args.output_dir, args.repo_id, api, args.keep_last_n)
        except Exception as exc:  # noqa: BLE001 - 監視ループは1回の失敗で落とさない
            print(f"[checkpoint_hub_gc] エラー（{args.interval}秒後にリトライ）: {exc}", file=sys.stderr)
        time.sleep(args.interval)


if __name__ == "__main__":
    main()
