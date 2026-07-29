#!/usr/bin/env bash
# 책갈피(Chaekgalpi) — WSL Ubuntu 내부 설치·실행 스크립트.
# windows/setup.ps1 이 root 로 호출한다.
#   provision : apt 로 Docker(docker.io + docker-compose-v2)·git 설치, wsl.conf 에 systemd 활성
#   run       : 소스 동기화 → docker compose up -d --build → /up 헬스체크 대기
set -euo pipefail

MODE="${1:-run}"
APP_DIR="/root/chaekgalpi"
REPO_URL="https://github.com/Cardanoian/bookmark_app.git"

provision() {
  export DEBIAN_FRONTEND=noninteractive
  echo "· 패키지 목록 갱신"
  apt-get update -y -qq
  echo "· Docker · git 설치"
  apt-get install -y -qq ca-certificates curl git docker.io docker-compose-v2
  # 다음 WSL 부팅부터 systemd 가 docker 데몬을 자동 기동하게 한다.
  if ! grep -qs "systemd=true" /etc/wsl.conf; then
    printf "[boot]\nsystemd=true\n" >> /etc/wsl.conf
  fi
  echo "· Ubuntu 구성 완료"
}

start_docker() {
  docker info >/dev/null 2>&1 && return 0
  systemctl start docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    docker info >/dev/null 2>&1 && return 0
    sleep 2
  done
  echo "Docker 데몬을 시작하지 못했습니다. 관리자 PowerShell 에서 'wsl --shutdown' 후 다시 실행해 보세요." >&2
  return 1
}

sync_source() {
  # SQLite·파일 I/O 성능을 위해 /mnt/c 가 아닌 WSL 파일시스템으로 소스를 옮겨 쓴다.
  if [ -n "${SRC_DIR:-}" ] && [ -f "$SRC_DIR/compose.yaml" ]; then
    echo "· Windows 쪽 소스 복사: $SRC_DIR → $APP_DIR (수 분 걸릴 수 있음)"
    rm -rf "$APP_DIR"
    mkdir -p "$APP_DIR"
    tar -C "$SRC_DIR" \
        --exclude="./.git" --exclude="./tmp" --exclude="./log" --exclude="./storage" \
        --exclude="./frontend/node_modules" --exclude="./script/output" --exclude="./script/.venv" \
        -cf - . | tar -C "$APP_DIR" -xf -
  elif [ -d "$APP_DIR/.git" ]; then
    echo "· 기존 체크아웃 갱신: $APP_DIR"
    git -C "$APP_DIR" pull --ff-only || true
  else
    echo "· GitHub 에서 소스 내려받기: $REPO_URL"
    git clone --depth 1 "$REPO_URL" "$APP_DIR"
  fi
}

run() {
  start_docker
  sync_source
  cd "$APP_DIR"
  echo "· 컨테이너 빌드·기동 (docker compose up -d --build)"
  docker compose up -d --build
  echo "· 서버 부팅·데모 데이터 적재 대기 중... (최초 1회는 십수 분까지 걸립니다)"
  for i in $(seq 1 240); do
    if curl -fs http://localhost:3000/up >/dev/null 2>&1; then
      echo "✅ 준비 완료: http://localhost:3000"
      return 0
    fi
    if [ $((i % 6)) -eq 0 ]; then
      echo "  … 진행 중 ($((i * 5 / 60))분 경과) — 로그는 windows\\logs.bat"
    fi
    sleep 5
  done
  echo "20분 안에 서버가 준비되지 않았습니다. windows\\logs.bat 로 로그를 확인하세요." >&2
  return 1
}

case "$MODE" in
  provision) provision ;;
  run)       run ;;
  *)         echo "usage: $0 {provision|run}" >&2; exit 2 ;;
esac
