#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
tripo-gen.py — 批量生成「送给你这个回来的人」的角色 & 道具

用法：
    pip install -r requirements.txt
    cp .env.example .env  # 填入 TRIPO_API_KEY
    python tripo-gen.py                       # 跑 tripo-prompts.json 里所有任务
    python tripo-gen.py --only xiaoman,aize   # 只跑指定 ID
    python tripo-gen.py --characters-only     # 只跑角色，跳过道具
    python tripo-gen.py --props-only          # 只跑道具

输出：
    out/models/<id>.glb                      # 默认
    out/models/<id>.metadata.json            # task_id / 时间戳 / 积分消耗
    out/tripo-gen.log                        # 完整日志

约束（来自 Tripo 官方文档 docs.tripo3d.ai）：
- 输出 URL 默认 5 分钟内过期，本脚本会在 success 后立刻下载
- 任务只能用发起它的 API key 查询
- 每个 text_to_model 任务大约 30~120s（P1）
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Any

import requests
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------

DEFAULT_PROMPTS_FILE = "tripo-prompts.json"
SCRIPT_DIR = Path(__file__).resolve().parent

# Tripo 任务终态
SUCCESS = "success"
FAILURE_STATUSES = {"failed", "banned", "expired", "cancelled"}

# ---------------------------------------------------------------------------
# 日志
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-7s | %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("tripo-gen")


# ---------------------------------------------------------------------------
# Tripo 客户端
# ---------------------------------------------------------------------------


class TripoError(RuntimeError):
    """Tripo API 调用失败。"""


class TripoClient:
    """Tripo OpenAPI 的最小封装，只用 requests。"""

    def __init__(self, api_key: str, base_url: str, timeout: int, poll_interval: int):
        if not api_key or api_key == "sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx":
            raise TripoError(
                "TRIPO_API_KEY 未配置。请把 .env.example 复制为 .env 并填入你的 key。"
            )
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.poll_interval = poll_interval
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            }
        )

    # ----- 公共方法 ---------------------------------------------------------

    def create_text_to_model(self, payload: dict[str, Any]) -> str:
        """提交 text_to_model 任务，返回 task_id。"""
        url = f"{self.base_url}/task"
        resp = self.session.post(url, json=payload, timeout=30)
        self._raise_for_status(resp)
        data = resp.json().get("data") or {}
        task_id = data.get("task_id")
        if not task_id:
            raise TripoError(f"响应缺少 task_id: {resp.text}")
        return task_id

    def wait_for_task(self, task_id: str) -> dict[str, Any]:
        """轮询直到任务结束（success / failure）。返回完整 data。"""
        url = f"{self.base_url}/task/{task_id}"
        deadline = time.monotonic() + self.timeout
        attempt = 0
        while True:
            if time.monotonic() > deadline:
                raise TripoError(f"任务 {task_id} 超时（>{self.timeout}s）")
            attempt += 1
            resp = self.session.get(url, timeout=30)
            self._raise_for_status(resp)
            data = resp.json().get("data") or {}
            status = data.get("status", "unknown")
            if status == SUCCESS:
                log.info("    ✓ task %s 成功（第 %d 次轮询）", task_id, attempt)
                return data
            if status in FAILURE_STATUSES:
                raise TripoError(f"任务 {task_id} 失败：{status} | {data.get('message', '')}")
            if attempt % 6 == 1:  # 每 30s 报告一次（默认 5s 间隔）
                log.info("    … task %s 状态=%s（已等 %ds）", task_id, status, (attempt - 1) * self.poll_interval)
            time.sleep(self.poll_interval)

    def download(self, url: str, dest: Path) -> None:
        """下载 Tripo 输出的 GLB。带流式 + 进度。"""
        log.info("    ↓ 下载 %s", Path(url).name)
        with self.session.get(url, stream=True, timeout=120) as resp:
            resp.raise_for_status()
            total = int(resp.headers.get("content-length", 0))
            written = 0
            with open(dest, "wb") as f:
                for chunk in resp.iter_content(chunk_size=64 * 1024):
                    if not chunk:
                        continue
                    f.write(chunk)
                    written += len(chunk)
                    if total:
                        pct = written / total * 100
                        if written % (512 * 1024) < 64 * 1024:  # 每 ~512KB 报一次
                            log.debug("      %d/%d bytes (%.0f%%)", written, total, pct)

    # ----- 内部 -------------------------------------------------------------

    @staticmethod
    def _raise_for_status(resp: requests.Response) -> None:
        if resp.status_code >= 400:
            raise TripoError(
                f"HTTP {resp.status_code} | URL={resp.url} | body={resp.text[:500]}"
            )


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------


def load_prompts(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise TripoError(f"找不到 prompt 文件：{path}")
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def build_task_payload(item: dict[str, Any], shared: dict[str, Any]) -> dict[str, Any]:
    """把一个角色/道具定义 + shared_params 拼成 Tripo API 的 task payload。"""
    payload: dict[str, Any] = {
        "type": "text_to_model",
        "model_version": shared["model_version"],
        "prompt": item["prompt"],
    }
    if "negative_prompt" in item:
        payload["negative_prompt"] = item["negative_prompt"]
    # 可选字段，Tripo 都接受 None；只发非空值更干净
    for key in ("face_limit", "texture", "pbr", "auto_size", "texture_quality"):
        if key in shared:
            payload[key] = shared[key]
    # 让同一角色多次跑结果一致（演示用，真实场景可去掉）
    payload["model_seed"] = abs(hash(item["id"])) % (2**31)
    return payload


def extract_glb_url(data: dict[str, Any]) -> str:
    """从 Tripo 任务的 output 字段里挑 GLB URL。"""
    output = data.get("output") or {}
    # 优先 PBR 模型（含光照贴图，移动端观感更好）；其次普通 model
    for key in ("pbr_model", "model", "base_model"):
        url = output.get(key)
        if url:
            return url
    raise TripoError(f"任务 output 中找不到模型 URL：{data}")


def run_one(
    client: TripoClient,
    item: dict[str, Any],
    shared: dict[str, Any],
    output_dir: Path,
    metadata: list[dict[str, Any]],
) -> None:
    item_id = item["id"]
    filename = item.get("filename", f"{item_id}.glb")
    dest = output_dir / filename

    log.info("▶ [%s] %s", item_id, item.get("display_name", ""))
    payload = build_task_payload(item, shared)
    log.debug("  payload: %s", json.dumps(payload, ensure_ascii=False)[:200])

    task_id = client.create_text_to_model(payload)
    log.info("  task_id = %s", task_id)

    data = client.wait_for_task(task_id)
    glb_url = extract_glb_url(data)
    log.info("  GLB URL = %s", glb_url[:80] + ("…" if len(glb_url) > 80 else ""))

    client.download(glb_url, dest)
    size_mb = dest.stat().st_size / (1024 * 1024)
    log.info("  ✓ 已保存 %s（%.2f MB）", dest.relative_to(SCRIPT_DIR), size_mb)

    metadata.append(
        {
            "id": item_id,
            "display_name": item.get("display_name", ""),
            "task_id": task_id,
            "filename": filename,
            "size_mb": round(size_mb, 2),
            "finished_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "prompt_chars": len(item["prompt"]),
        }
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Tripo 批量生成 3D 模型")
    parser.add_argument("--prompts", default=str(SCRIPT_DIR / DEFAULT_PROMPTS_FILE))
    parser.add_argument("--only", help="逗号分隔的 ID 白名单，例如 xiaoman,aize")
    parser.add_argument("--characters-only", action="store_true")
    parser.add_argument("--props-only", action="store_true")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    load_dotenv(SCRIPT_DIR / ".env")

    api_key = os.getenv("TRIPO_API_KEY", "")
    base_url = os.getenv("TRIPO_BASE_URL", "https://api.tripo3d.ai/v2/openapi")
    output_dir = Path(os.getenv("OUTPUT_DIR", "./out/models")).resolve()
    poll_interval = int(os.getenv("POLL_INTERVAL", "5"))
    timeout = int(os.getenv("TASK_TIMEOUT", "300"))

    output_dir.mkdir(parents=True, exist_ok=True)
    # 日志也写到 out/
    file_handler = logging.FileHandler(output_dir.parent / "tripo-gen.log", encoding="utf-8")
    file_handler.setFormatter(logging.Formatter("%(asctime)s | %(levelname)-7s | %(message)s"))
    logging.getLogger().addHandler(file_handler)

    log.info("输出目录：%s", output_dir)
    log.info("API base：%s", base_url)
    log.info("轮询间隔：%ds，单任务超时：%ds", poll_interval, timeout)

    client = TripoClient(api_key, base_url, timeout, poll_interval)

    prompts = load_prompts(Path(args.prompts))
    shared = prompts.get("shared_params", {})
    items: list[dict[str, Any]] = []
    if not args.props_only:
        items.extend(prompts.get("characters", []))
    if not args.characters_only:
        items.extend(prompts.get("props", []))
    if args.only:
        wanted = {w.strip() for w in args.only.split(",")}
        items = [it for it in items if it["id"] in wanted]
    if not items:
        log.error("没有可生成的任务（prompt 文件里为空或 --only 过滤掉了所有）")
        return 2

    log.info("本次将生成 %d 个模型：%s", len(items), ", ".join(it["id"] for it in items))

    metadata: list[dict[str, Any]] = []
    failed: list[tuple[str, str]] = []
    started = time.time()

    for item in items:
        try:
            run_one(client, item, shared, output_dir, metadata)
        except Exception as exc:  # noqa: BLE001
            log.error("✗ [%s] 失败：%s", item["id"], exc)
            failed.append((item["id"], str(exc)))

    elapsed = time.time() - started

    # 写 metadata
    meta_path = output_dir / "metadata.json"
    with meta_path.open("w", encoding="utf-8") as f:
        json.dump(
            {
                "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "elapsed_seconds": round(elapsed, 1),
                "base_url": base_url,
                "model_version": shared.get("model_version"),
                "items": metadata,
                "failed": [{"id": fid, "reason": reason} for fid, reason in failed],
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

    log.info("=" * 60)
    log.info("完成：成功 %d / 失败 %d，耗时 %.1fs", len(metadata), len(failed), elapsed)
    log.info("清单已写入：%s", meta_path)
    log.info("下一步：把 out/models/*.glb 拷到 Maker 项目的 assets/models/")

    if failed:
        log.warning("失败清单：%s", ", ".join(fid for fid, _ in failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())