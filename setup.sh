#!/usr/bin/env bash
# 책갈피(Chaekgalpi) — 개발 환경 한 번에 준비하기 (Linux · macOS · WSL2 Ubuntu 공통)
#
#   ./setup.sh                  시스템 패키지 → mise → Ruby(.ruby-version, precompiled) → 젬 → DB·시드
#   ./setup.sh --run            준비가 끝나면 그대로 bin/dev 로 서버까지 띄운다
#   ./setup.sh --skip-packages  시스템 패키지(apt/dnf/pacman/brew) 단계를 건너뛴다
#   ./setup.sh --dry-run        실제로 실행하지 않고 할 일만 출력한다
#
# 몇 번을 다시 실행해도 같은 결과가 나온다(멱등). 이미 깔린 것은 건너뛴다.
# Windows 는 WSL2 Ubuntu 안에서 실행한다 — README.md「환경 설정 › Windows」.
set -euo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$APP_ROOT"

# Ruby 버전의 단일 진실은 .ruby-version("ruby-4.0.5") 이다. Dockerfile 의 RUBY_VERSION 과 같아야 한다.
RUBY_VERSION="$(sed -e 's/^ruby-//' -e 's/[[:space:]]//g' .ruby-version)"
MISE_BIN="${MISE_INSTALL_PATH:-$HOME/.local/bin/mise}"

DRY_RUN=0 SKIP_PACKAGES=0 RUN_SERVER=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=1 ;;
    --skip-packages) SKIP_PACKAGES=1 ;;
    --run)           RUN_SERVER=1 ;;
    -h|--help)       sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "알 수 없는 옵션: $arg (--help 참고)" >&2; exit 2 ;;
  esac
done

say()  { printf '\n\033[1;34m· %s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die()  { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = 1 ]; then note "\$ $*"; else "$@"; fi; }

# ── 어디서 돌고 있나 ────────────────────────────────────────────────────────
OS="$(uname -s)" ARCH="$(uname -m)" DISTRO="" IS_WSL=0 IS_MUSL=0
if [ "$OS" = Linux ] && [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  DISTRO="$(. /etc/os-release && echo "${ID:-} ${ID_LIKE:-}")"
fi
if grep -qi microsoft /proc/version 2>/dev/null; then IS_WSL=1; fi
if [ "$OS" = Linux ] && ldd --version 2>&1 | grep -qi musl; then IS_MUSL=1; fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || die "sudo 가 없습니다. root 로 실행하거나 sudo 를 먼저 설치하세요."
  SUDO="sudo"
fi

# ── 1. 시스템 패키지 — Dockerfile.dev 와 같은 목록 ───────────────────────────
# shellcheck disable=SC2086
install_packages() {
  case "$OS" in
    Darwin)
      if ! xcode-select -p >/dev/null 2>&1; then
        note "Xcode 명령줄 도구 설치 창이 뜹니다 — [설치] 를 누르고, 끝나면 이 스크립트를 다시 실행하세요."
        run xcode-select --install
        [ "$DRY_RUN" = 1 ] || exit 0
      fi
      command -v brew >/dev/null 2>&1 \
        || die "Homebrew 가 없습니다. https://brew.sh 의 설치 명령을 먼저 실행한 뒤 다시 시도하세요."
      run brew install git libvips                       # SQLite 는 macOS 기본 포함
      # Intel 맥은 미리 컴파일된 Ruby 가 없어 소스 빌드 → 빌드 의존성까지 갖춘다.
      [ "$ARCH" = arm64 ] || run brew install openssl@3 libyaml gmp autoconf
      ;;
    Linux)
      case " $DISTRO " in
        *debian*|*ubuntu*)
          run $SUDO apt-get update -qq
          run $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            build-essential git curl ca-certificates pkg-config libyaml-dev sqlite3 libsqlite3-dev libvips ;;
        *fedora*|*rhel*|*centos*)
          run $SUDO dnf install -y gcc gcc-c++ make git curl pkgconf-pkg-config libyaml-devel sqlite sqlite-devel vips ;;
        *arch*)
          run $SUDO pacman -S --needed --noconfirm base-devel git curl libyaml sqlite libvips ;;
        *)
          note "자동 설치를 모르는 배포판입니다: $DISTRO"
          note "C 컴파일러·make · git · curl · pkg-config · libyaml(dev) · sqlite3(+dev) · libvips 를 직접 설치한 뒤"
          die  "./setup.sh --skip-packages 로 다시 실행하세요." ;;
      esac ;;
    *) die "지원하지 않는 OS: $OS (Linux · macOS · WSL2 Ubuntu 만 지원)" ;;
  esac
}

# ── 2. mise — Ruby 버전 관리자 ─────────────────────────────────────────────
install_mise() {
  if command -v mise >/dev/null 2>&1; then
    MISE_BIN="$(command -v mise)"
    note "mise 있음: $MISE_BIN ($("$MISE_BIN" --version 2>/dev/null | head -1))"
  elif [ -x "$MISE_BIN" ]; then
    note "mise 있음(아직 PATH 엔 없음): $MISE_BIN"
  elif [ "$OS" = Darwin ] && command -v brew >/dev/null 2>&1; then
    run brew install mise
    MISE_BIN="$(brew --prefix)/bin/mise"
  else
    run sh -c 'curl -fsSL https://mise.run | sh'          # → ~/.local/bin/mise
  fi

  # 셸 시작 파일에 activate 한 줄 — 새 터미널부터 프로젝트 폴더에서 ruby 가 자동으로 잡힌다.
  local shell_name rc line
  shell_name="$(basename "${SHELL:-bash}")"
  case "$shell_name" in
    zsh)  rc="$HOME/.zshrc";                   line="eval \"\$($MISE_BIN activate zsh)\"" ;;
    fish) rc="$HOME/.config/fish/config.fish"; line="$MISE_BIN activate fish | source" ;;
    *)    rc="$HOME/.bashrc";                  line="eval \"\$($MISE_BIN activate bash)\"" ;;
  esac
  if [ -f "$rc" ] && grep -q "mise activate" "$rc"; then
    note "$rc 에 mise activate 이미 있음"
  elif [ "$DRY_RUN" = 1 ]; then
    note "\$ echo '$line' >> $rc"
  else
    mkdir -p "$(dirname "$rc")"
    printf '\n# mise — 책갈피 setup.sh 가 추가\n%s\n' "$line" >> "$rc"
    note "$rc 에 mise activate 추가"
  fi
}

# ── 3. Ruby — 미리 컴파일된 바이너리로 ──────────────────────────────────────
install_ruby() {
  if [ "$DRY_RUN" = 0 ] && [ ! -x "$MISE_BIN" ]; then die "mise 를 찾지 못했습니다: $MISE_BIN"; fi

  # mise 가 저장소의 .ruby-version 을 읽게 한다(기본은 mise.toml 만 읽음). 버전 선언은 그 파일 하나뿐이다.
  if "$MISE_BIN" settings get idiomatic_version_file_enable_tools 2>/dev/null | grep -qw ruby; then
    note "mise 가 .ruby-version 을 읽도록 이미 설정됨"
  else
    run "$MISE_BIN" settings add idiomatic_version_file_enable_tools ruby
  fi

  # 미리 컴파일된 바이너리는 glibc x86_64/arm64 리눅스 · Apple Silicon 에만 있다. 소스 빌드보다 훨씬
  # 빠르고(수 분 → 수십 초) OpenSSL·gmp 같은 빌드 의존성을 맞출 필요가 없다.
  local precompiled=1
  if [ "$IS_MUSL" = 1 ]; then precompiled=0; note "musl 리눅스(Alpine 등) — 미리 컴파일된 Ruby 가 없어 소스 빌드"; fi
  if [ "$OS" = Darwin ] && [ "$ARCH" != arm64 ]; then precompiled=0; note "Intel 맥 — 미리 컴파일된 Ruby 가 없어 소스 빌드"; fi
  if [ "$precompiled" = 1 ]; then
    run "$MISE_BIN" settings set ruby.compile false
  else
    run "$MISE_BIN" settings unset ruby.compile || true
  fi

  run "$MISE_BIN" install "ruby@$RUBY_VERSION"            # 이미 있으면 건너뜀
  run "$MISE_BIN" exec "ruby@$RUBY_VERSION" -- ruby -v
}

# ── 4. 젬 · DB · 시드 ───────────────────────────────────────────────────────
prepare_app() {
  local mx=("$MISE_BIN" exec "ruby@$RUBY_VERSION" --)
  run "${mx[@]}" gem install foreman --conservative       # bin/dev 의 프로세스 관리자(없으면 bin/dev 가 첫 실행 때 설치)
  run "${mx[@]}" bin/setup --skip-server                  # bundle install → db:prepare(스키마+시드) → log/tmp 정리
}

# ── 실행 ────────────────────────────────────────────────────────────────────
say "책갈피 개발 환경 준비 — $OS $ARCH ${DISTRO:+($DISTRO) }· Ruby $RUBY_VERSION"
if [ "$IS_WSL" = 1 ]; then
  case "$APP_ROOT" in
    /mnt/*) note "⚠ WSL2 인데 소스가 윈도우 디스크($APP_ROOT)에 있습니다. ~/ 아래로 옮기면 훨씬 빠릅니다(README「환경 설정 › Windows」)." ;;
  esac
fi

if [ "$SKIP_PACKAGES" = 1 ]; then
  say "1/4 시스템 패키지 — 건너뜀(--skip-packages)"
else
  say "1/4 시스템 패키지"
  install_packages
fi
say "2/4 mise";                install_mise
say "3/4 Ruby $RUBY_VERSION";  install_ruby
say "4/4 젬 · DB · 시드";      prepare_app

say "준비 완료"
note "서버 실행:  bin/dev   →  http://localhost:3000  (로그인 화면 아래 「🚀 바로 체험해 보기」)"
note "이 터미널에서는 먼저  exec \$SHELL -l  로 셸을 다시 읽어야 ruby 가 잡힙니다(새 터미널은 자동)."
if [ "$RUN_SERVER" = 1 ]; then
  say "bin/dev 실행 (--run)"
  if [ "$DRY_RUN" = 1 ]; then note "\$ bin/dev"; else exec "$MISE_BIN" exec "ruby@$RUBY_VERSION" -- bin/dev; fi
fi
