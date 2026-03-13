#!/usr/bin/env bash
set -euo pipefail

DOC_NAME="${1:-}"

cd /data/xfeng/ragflow/docker
docker compose exec -T -e DOC_NAME="$DOC_NAME" ragflow-gpu python3 - <<'PY'
import os
import re
import glob
import time
import sys
from datetime import datetime, timedelta
from collections import Counter

sys.path.insert(0, "/ragflow")
from common.settings import init_settings
init_settings()
from api.db.db_models import Document, Task

def fmt_dur(sec: float) -> str:
    if sec < 1:
        return f"{int(sec * 1000)}ms"
    if sec < 60:
        return f"{sec:.2f}s"
    h = int(sec // 3600)
    sec -= h * 3600
    m = int(sec // 60)
    s = int(round(sec - m * 60))
    if h > 0:
        return f"{h}h{m}m{s}s"
    return f"{m}m{s}s"

ctx = {}
DOC_NAME = (os.environ.get("DOC_NAME") or "").strip()

def run_step(i, total, name, fn):
    st = time.perf_counter()
    print(f"当前执行第{i}/{total}步骤: {name} 开始时间:{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    fn()
    print(f"第{i}/{total}步骤执行完成,共耗时{fmt_dur(time.perf_counter() - st)}")

def step1():
    if DOC_NAME:
        q = Document.select().where(Document.name == DOC_NAME).order_by(Document.create_time.desc())
    else:
        q = Document.select().where(Document.process_begin_at.is_null(False)).order_by(Document.process_begin_at.desc())
    doc = q.first()
    if not doc:
        raise SystemExit("未找到文档")

    task_ids = {t.id for t in Task.select(Task.id).where(Task.doc_id == doc.id)}
    start = doc.process_begin_at
    wall = float(doc.process_duration or 0.0)
    if not start:
        raise SystemExit("文档没有 process_begin_at，无法对齐日志时间窗")

    end = start + timedelta(seconds=wall if wall > 0 else 7200)
    ctx.update({
        "doc": doc,
        "task_ids": task_ids,
        "w0": start - timedelta(minutes=5),
        "w1": end + timedelta(minutes=5),
        "wall": wall,
    })

def iter_lines():
    ts_re = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),")
    for fp in glob.glob("/ragflow/logs/task_executor*.log"):
        with open(fp, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                m = ts_re.match(line)
                if not m:
                    continue
                ts = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
                if ts < ctx["w0"] or ts > ctx["w1"]:
                    continue
                yield line

def step2():
    r_done = re.compile(r"set_progress\((?P<tid>[0-9a-f]{32})\).*Task done \((?P<t>[0-9.]+)s\)")
    r_ocr = re.compile(r"set_progress\((?P<tid>[0-9a-f]{32})\).*OCR finished \((?P<t>[0-9.]+)s\)")
    r_lay = re.compile(r"set_progress\((?P<tid>[0-9a-f]{32})\).*Layout analysis \((?P<t>[0-9.]+)s\)")
    r_emb = re.compile(r"set_progress\((?P<tid>[0-9a-f]{32})\).*Embedding chunks \((?P<t>[0-9.]+)s\)")

    s = {
        "done": 0.0, "ocr": 0.0, "layout": 0.0, "embed": 0.0,
        "n_done": 0, "n_ocr": 0, "n_layout": 0, "n_embed": 0
    }
    tids = ctx["task_ids"]

    for line in iter_lines():
        m = r_done.search(line)
        if m and m.group("tid") in tids:
            s["done"] += float(m.group("t")); s["n_done"] += 1; continue
        m = r_ocr.search(line)
        if m and m.group("tid") in tids:
            s["ocr"] += float(m.group("t")); s["n_ocr"] += 1; continue
        m = r_lay.search(line)
        if m and m.group("tid") in tids:
            s["layout"] += float(m.group("t")); s["n_layout"] += 1; continue
        m = r_emb.search(line)
        if m and m.group("tid") in tids:
            s["embed"] += float(m.group("t")); s["n_embed"] += 1; continue

    ctx["parse"] = s

def step3():
    r_put = re.compile(r"(?P<label>[A-Z_ ]*PUT)\((?P<name>.+?)\)\s*cost\s*(?P<t>[0-9.]+)\s*s", re.I)
    total = 0.0
    n = 0
    labels = Counter()
    doc_name = ctx["doc"].name

    for line in iter_lines():
        m = r_put.search(line)
        if not m:
            continue
        nm = os.path.basename(m.group("name").strip())
        if nm != doc_name:
            continue
        total += float(m.group("t"))
        n += 1
        labels[m.group("label").strip().upper()] += 1

    ctx["put"] = {"sum": total, "n": n, "labels": labels}

def step4():
    p = ctx["parse"]
    put = ctx["put"]["sum"]
    wall = ctx["wall"]
    ctx["pct"] = {
        "done": (put / p["done"] * 100.0) if p["done"] > 0 else 0.0,
        "wall": (put / wall * 100.0) if wall > 0 else 0.0,
    }

def step5():
    doc = ctx["doc"]
    p = ctx["parse"]
    put = ctx["put"]
    pct = ctx["pct"]
    label = put["labels"].most_common(1)[0][0] if put["labels"] else "PUT"

    print(f"doc_id={doc.id} name={doc.name}")
    print(f"task_count={len(ctx['task_ids'])} wall_clock={ctx['wall']:.2f}s")
    print(f"sum_task_done={p['done']:.2f}s (n={p['n_done']})")
    print(f"sum_ocr={p['ocr']:.2f}s (n={p['n_ocr']}) sum_layout={p['layout']:.2f}s (n={p['n_layout']}) sum_embed={p['embed']:.2f}s (n={p['n_embed']})")
    print(f"sum_storage_write(log={label})={put['sum']:.2f}s (n={put['n']})")
    print(f"storage_write_pct_of_sum_task_done={pct['done']:.2f}%")
    print(f"storage_write_pct_of_wall_clock={pct['wall']:.2f}%")
    print("备注: OCR/Embedding 为并行子任务累计耗时，可能大于 wall_clock。")

run_step(1, 5, "检查文档与命名", step1)
run_step(2, 5, "解析阶段耗时聚合(OCR/Layout/Embedding)", step2)
run_step(3, 5, "统计存储写入耗时", step3)
run_step(4, 5, "计算占比", step4)
run_step(5, 5, "输出结果", step5)
PY
