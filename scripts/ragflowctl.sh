#!/usr/bin/env bash
set -euo pipefail

ROOT="/data/xfeng/ragflow"
DOCKER_DIR="$ROOT/docker"
cd "$DOCKER_DIR"

get_env() {
  local key="$1"
  awk -F= -v k="$key" '$1==k {print $2; exit}' .env | tr -d '\r' || true
}

DOC_ENGINE="$(get_env DOC_ENGINE)"
DOC_ENGINE="${DOC_ENGINE:-elasticsearch}"
STORAGE_IMPL="$(get_env STORAGE_IMPL)"
STORAGE_IMPL="${STORAGE_IMPL:-MINIO}"

case "${DOC_ENGINE,,}" in
  elasticsearch) DOC_SVC="es01" ;;
  infinity)      DOC_SVC="infinity" ;;
  opensearch)    DOC_SVC="opensearch01" ;;
  *) echo "Unknown DOC_ENGINE=$DOC_ENGINE, fallback to es01"; DOC_SVC="es01" ;;
esac

SERVICES=(mysql redis "$DOC_SVC" ragflow-gpu)
if [[ "${STORAGE_IMPL^^}" != "LOCAL_FS" ]]; then
  SERVICES+=(minio)
fi

usage() {
  cat <<USAGE
Usage: $0 {start|stop|restart|status|logs [service]|env|plan}
  start    Start ragflow-gpu + required deps
  stop     Stop ragflow-gpu + deps
  restart  Recreate ragflow-gpu only
  status   docker compose ps
  logs     Tail logs (default service: ragflow-gpu)
  env      Show key runtime env in ragflow-gpu
  plan     Show resolved startup plan
USAGE
}

cmd="${1:-}"
case "$cmd" in
  start)
    docker compose --profile gpu up -d "${SERVICES[@]}"
    ;;
  stop)
    docker compose stop "${SERVICES[@]}"
    ;;
  restart)
    docker compose up -d --no-deps --force-recreate ragflow-gpu
    ;;
  status)
    docker compose ps
    ;;
  logs)
    docker compose logs -f --tail=200 "${2:-ragflow-gpu}"
    ;;
  env)
    docker compose exec ragflow-gpu bash -lc 'echo STORAGE_IMPL=$STORAGE_IMPL TASK_EXECUTOR_NUM=$TASK_EXECUTOR_NUM MAX_CONCURRENT_TASKS=$MAX_CONCURRENT_TASKS MAX_CONCURRENT_CHUNK_BUILDERS=$MAX_CONCURRENT_CHUNK_BUILDERS OCR_GPU_MEM_LIMIT_MB=$OCR_GPU_MEM_LIMIT_MB USE_MINERU=$USE_MINERU'
    ;;
  plan)
    echo "DOC_ENGINE=$DOC_ENGINE STORAGE_IMPL=$STORAGE_IMPL"
    echo "SERVICES=${SERVICES[*]}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
