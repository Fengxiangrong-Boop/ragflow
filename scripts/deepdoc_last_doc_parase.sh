#!/usr/bin/env bash
set -euo pipefail

# 用法:
#   bash /data/xfeng/ragflow/scripts/deepdoc_last_doc_parase.sh "78M.pdf"
#   bash /data/xfeng/ragflow/scripts/deepdoc_last_doc_parase.sh
# 不传文档名时，默认统计最近一条已开始解析(process_begin_at非空)的文档。

DOC_NAME="${1:-}"

cd /data/xfeng/ragflow/docker

docker compose exec -T -e DOC_NAME="$DOC_NAME" ragflow-gpu python3 - <<'PY'
import os
import re
import glob
import sys
from datetime import datetime, timedelta
from collections import Counter

sys.path.insert(0, "/ragflow")
from common.settings import init_settings
init_settings()
from api.db.db_models import Document, Task

doc_name = (os.environ.get("DOC_NAME") or "").strip()

if doc_name:
    doc = (
        Document.select()
        .where(Document.name == doc_name)
        .order_by(Document.create_time.desc())
        .first()
    )
else:
    doc = (
        Document.select()
        .where(Document.process_begin_at.is_null(False))
        .order_by(Document.process_begin_at.desc())
        .first()
    )

if not doc:
    raise SystemExit(f"未找到文档: {doc_name}" if doc_name else "未找到最近已解析文档")

task_ids = {t.id for t in Task.select(Task.id).where(Task.doc_id == doc.id)}
start = doc.process_begin_at
duration = float(doc.process_duration or 0.0)

if not start:
    raise SystemExit("process_begin_at 为空，无法统计")

# 加缓冲窗口，避免漏统计
end = start + timedelta(seconds=duration if duration > 0 else 7200)
w0, w1 = start - timedelta(minutes=5), end + timedelta(minutes=5)

ts_re = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),")
r_done = re.compile(r"set_progress\((?P<tid>[0-9a-f]{32})\).*Task done \((?P<t>[0-9.]+)s\)")
r_ocr  = re.compile(r"set_progress\((?P<tid>[0-9a-f]{32})\).*OCR finished \((?P<t>[0-9.]+)s\)")
r_lay  = re.compile(r"set_progress\((?P<tid>[0-9a-f]{32})\).*Layout analysis \((?P<t>[0-9.]+)s\)")
r_emb  = re.compile(r"set_progress\((?P<tid>[0-9a-f]{32})\).*Embedding chunks \((?P<t>[0-9.]+)s\)")
r_put  = re.compile(r"(?P<label>[A-Z_ ]*PUT)\((?P<name>.+?)\)\s*cost\s*(?P<t>[0-9.]+)\s*s", re.I)

sum_done = sum_ocr = sum_lay = sum_emb = sum_put = 0.0
n_done = n_ocr = n_lay = n_emb = n_put = 0
put_labels = Counter()

for fp in sorted(glob.glob("/ragflow/logs/task_executor*.log")):
    with open(fp, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            mt = ts_re.match(line)
            if not mt:
                continue
            ts = datetime.strptime(mt.group(1), "%Y-%m-%d %H:%M:%S")
            if ts < w0 or ts > w1:
                continue

            m = r_done.search(line)
            if m and m.group("tid") in task_ids:
                sum_done += float(m.group("t")); n_done += 1; continue

            m = r_ocr.search(line)
            if m and m.group("tid") in task_ids:
                sum_ocr += float(m.group("t")); n_ocr += 1; continue

            m = r_lay.search(line)
            if m and m.group("tid") in task_ids:
                sum_lay += float(m.group("t")); n_lay += 1; continue

            m = r_emb.search(line)
            if m and m.group("tid") in task_ids:
                sum_emb += float(m.group("t")); n_emb += 1; continue

            m = r_put.search(line)
            if m:
                nm = os.path.basename(m.group("name").strip())
                if nm == doc.name:
                    sum_put += float(m.group("t")); n_put += 1
                    put_labels[m.group("label").strip().upper()] += 1

print(f"doc_id={doc.id} name={doc.name}")
print(f"task_count={len(task_ids)} wall_clock={duration:.2f}s")
print(f"sum_task_done={sum_done:.2f}s (n={n_done})")
print(f"sum_ocr={sum_ocr:.2f}s (n={n_ocr}) sum_layout={sum_lay:.2f}s (n={n_lay}) sum_embed={sum_emb:.2f}s (n={n_emb})")
print(f"sum_storage_put(log=PUT)={sum_put:.2f}s (n={n_put})")

if sum_done > 0:
    print(f"storage_put_pct_of_sum_task_done={sum_put / sum_done * 100:.2f}%")
if duration > 0:
    print(f"storage_put_pct_of_wall_clock={sum_put / duration * 100:.2f}%")
if put_labels:
    print("put_log_labels=", dict(put_labels))

print("备注: OCR/Embedding 为并行子任务累计耗时，可能大于 wall_clock。")
PY

