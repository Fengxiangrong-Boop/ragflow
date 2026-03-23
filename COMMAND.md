-标准指令清单

CPU 模式（ragflow-cpu）：

切目录（配置参数修改）
cd /data/xfeng/ragflow/docker

1.存储后端设置（MINIO 或 LOCAL_FS）
# 改成 MINIO
sed -i 's/^STORAGE_IMPL=.*/STORAGE_IMPL=MINIO/' .env

# 改成 LOCAL_FS
sed -i 's/^STORAGE_IMPL=.*/STORAGE_IMPL=LOCAL_FS/' .env

2.任务并行度设置
sed -i 's/^TASK_EXECUTOR_NUM=.*/TASK_EXECUTOR_NUM=4/' .env

3.重建生效（CPU）
docker compose stop ragflow-gpu 2>/dev/null || true
docker compose --profile cpu up -d --no-deps --force-recreate ragflow-cpu

4.查询当前配置（CPU）
bash /data/xfeng/ragflow/scripts/ragflowctl.sh env

5.监控上传日志
truncate -s 0 ragflow-logs/upload.log
tail -F ragflow-logs/upload.log

6.打印解析日志
bash /data/xfeng/ragflow/scripts/deepdoc_last_doc_parase.sh "文件名.pdf"

===============================================================================

GPU 模式（ragflow-gpu）：

切目录（配置参数修改）
cd /data/xfeng/ragflow/docker

1.存储后端设置（MINIO 或 LOCAL_FS）
# 改成 MINIO
sed -i 's/^STORAGE_IMPL=.*/STORAGE_IMPL=MINIO/' .env

# 改成 LOCAL_FS
sed -i 's/^STORAGE_IMPL=.*/STORAGE_IMPL=LOCAL_FS/' .env

2.任务并行度设置
sed -i 's/^TASK_EXECUTOR_NUM=.*/TASK_EXECUTOR_NUM=4/' .env

3.重建生效（GPU）
docker compose stop ragflow-cpu 2>/dev/null || true
docker compose --profile gpu up -d --no-deps --force-recreate ragflow-gpu

4.查询当前配置（GPU）
bash /data/xfeng/ragflow/scripts/ragflowctl.sh env
docker compose exec ragflow-gpu bash -lc 'nvidia-smi -L'

5.监控上传日志
truncate -s 0 ragflow-logs/upload.log
tail -F ragflow-logs/upload.log

6.打印解析日志
bash /data/xfeng/ragflow/scripts/deepdoc_last_doc_parase.sh "文件名.pdf"