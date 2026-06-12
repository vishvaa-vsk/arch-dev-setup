#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly AUR_BASE_URL="https://aur.archlinux.org"
readonly POSTGRES_DATA_DIR="/var/lib/postgres/data"

log() {
  printf '\n\033[1;34m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*"
}

warn() {
  printf '\n\033[1;33m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*" >&2
}

die() {
  printf '\n\033[1;31m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

on_error() {
  local exit_code=$?
  printf '\n\033[1;31m[%s]\033[0m Failed at line %s (exit code %s).\n' \
    "$SCRIPT_NAME" "$1" "$exit_code" >&2
  exit "$exit_code"
}
trap 'on_error "$LINENO"' ERR

if [[ ${EUID} -eq 0 ]]; then
  die "Run this script as your normal user, not as root."
fi

[[ -r /etc/os-release ]] || die "Cannot identify this Linux distribution."
# shellcheck disable=SC1091
source /etc/os-release

case " ${ID:-} ${ID_LIKE:-} " in
  *" arch "*)
    ;;
  *)
    die "This installer supports Arch Linux and Arch-based distributions such as CachyOS."
    ;;
esac

command -v sudo >/dev/null || die "sudo is required."
command -v pacman >/dev/null || die "pacman is required."

readonly TARGET_USER="$USER"

install_repo_packages() {
  local packages=(
    base-devel
    git
    curl
    ca-certificates
    docker
    docker-buildx
    docker-compose
    github-cli
    postgresql
    python
    nvm
    pnpm
    bun
    uv
    msedit
  )

  log "Updating the system and installing official repository packages"
  sudo pacman -Syu --needed --noconfirm "${packages[@]}"
}

install_yay() {
  if command -v yay >/dev/null; then
    return
  fi

  local build_dir
  build_dir="$(mktemp -d)"

  log "Installing the yay AUR helper"
  git clone "${AUR_BASE_URL}/yay-bin.git" "$build_dir/yay-bin"
  (
    cd "$build_dir/yay-bin"
    makepkg -si --needed --noconfirm
  )
  rm -rf "$build_dir"
}

install_aur_git_package() {
  local package_name="$1"
  local build_dir
  build_dir="$(mktemp -d)"

  log "Building ${package_name} from ${AUR_BASE_URL}/${package_name}.git"
  git clone "${AUR_BASE_URL}/${package_name}.git" "$build_dir/$package_name"
  (
    cd "$build_dir/$package_name"
    makepkg -si --needed --noconfirm
  )
  rm -rf "$build_dir"
}

remove_valkey() {
  if pacman -Q valkey >/dev/null 2>&1; then
    log "Removing Valkey so actual Redis can be installed"
    sudo pacman -R --noconfirm valkey
  fi
}

install_aur_packages() {
  local packages=(
    visual-studio-code-bin
    pgadmin4-desktop
    brave-bin
    localsend-bin
  )

  log "Installing packages available through yay"
  yay -S --needed --noconfirm "${packages[@]}"
}

configure_docker() {
  log "Enabling Docker and granting ${TARGET_USER} access to its socket"
  sudo systemctl enable --now docker.service
  sudo usermod -aG docker "$TARGET_USER"
}

configure_postgresql() {
  log "Initializing and enabling PostgreSQL"
  if [[ ! -f "${POSTGRES_DATA_DIR}/PG_VERSION" ]]; then
    sudo install -d -o postgres -g postgres -m 700 "$POSTGRES_DATA_DIR"
    sudo -u postgres initdb --locale=C.UTF-8 -E UTF8 -D "$POSTGRES_DATA_DIR"
  fi
  sudo systemctl enable --now postgresql.service
}

configure_redis() {
  log "Enabling Redis"
  if systemctl list-unit-files redis.service --no-legend 2>/dev/null | grep -q '^redis.service'; then
    sudo systemctl enable --now redis.service
    return
  fi

  warn "redis.service was not found. Redis was installed, but its service must be started manually."
}

configure_nvm_and_node() {
  local nvm_init="/usr/share/nvm/init-nvm.sh"
  local init_line='[ -s /usr/share/nvm/init-nvm.sh ] && source /usr/share/nvm/init-nvm.sh'
  [[ -r "$nvm_init" ]] || die "NVM initialization script was not found at ${nvm_init}."

  for shell_config in "$HOME/.bashrc" "$HOME/.zshrc"; do
    touch "$shell_config"
    if ! grep -Fqx "$init_line" "$shell_config"; then
      printf '\n%s\n' "$init_line" >>"$shell_config"
    fi
  done

  log "Installing the latest Node.js release through NVM"
  bash -c "source '$nvm_init'; nvm install node; nvm alias default node"
}

print_summary() {
  cat <<EOF

Setup complete.

Installed:
  - Visual Studio Code (Microsoft build) and Antigravity
  - Docker Engine, Buildx, and Compose
  - Redis and redis-cli
  - PostgreSQL and pgAdmin 4 Desktop
  - GitHub CLI and Microsoft Edit
  - Python, uv, Node.js through NVM, pnpm, and Bun
  - Brave Browser and LocalSend

Log out and back in before using Docker without sudo.
Authenticate GitHub CLI with: gh auth login
EOF
}

main() {
  sudo -v
  install_repo_packages
  install_yay
  remove_valkey
  install_aur_git_package antigravity
  install_aur_git_package redis
  install_aur_packages
  configure_docker
  configure_postgresql
  configure_redis
  configure_nvm_and_node
  print_summary
}

main "$@"
