#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly AUR_BASE_URL="https://aur.archlinux.org"
readonly POSTGRES_DATA_DIR="/var/lib/postgres/data"

AUR_HELPER=""

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
    ghostty
    github-cli
    hyprlock
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

select_aur_helper() {
  if command -v yay >/dev/null; then
    AUR_HELPER="yay"
    log "Using the installed yay AUR helper"
    return
  fi

  if command -v paru >/dev/null; then
    AUR_HELPER="paru"
    log "Using the installed paru AUR helper"
    return
  fi

  printf '\nNo AUR helper was found. Select one to install:\n'
  printf '  1) yay\n'
  printf '  2) paru\n'

  while [[ -z "$AUR_HELPER" ]]; do
    read -r -p "Enter 1 or 2: " selection || die "Unable to read AUR helper selection."
    case "$selection" in
      1 | yay)
        AUR_HELPER="yay"
        ;;
      2 | paru)
        AUR_HELPER="paru"
        ;;
      *)
        warn "Invalid selection. Enter 1 for yay or 2 for paru."
        ;;
    esac
  done
}

install_aur_helper() {
  if command -v "$AUR_HELPER" >/dev/null; then
    return
  fi

  local build_dir
  build_dir="$(mktemp -d)"

  log "Building and installing the ${AUR_HELPER} AUR helper"
  git clone "${AUR_BASE_URL}/${AUR_HELPER}.git" "$build_dir/$AUR_HELPER"
  (
    cd "$build_dir/$AUR_HELPER"
    makepkg -si --needed --noconfirm
  )
  rm -rf "$build_dir"
}

install_aur_git_package() {
  local package_name="$1"
  if pacman -Q "$package_name" >/dev/null 2>&1; then
    log "Package ${package_name} is already installed. Skipping build."
    return
  fi

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
    pgadmin4-desktop-bin
    brave-bin
    localsend-bin
  )

  log "Installing packages available through ${AUR_HELPER}"
  "$AUR_HELPER" -S --needed --noconfirm "${packages[@]}"
}

configure_docker() {
  log "Enabling Docker and granting ${TARGET_USER} access to its socket"
  sudo systemctl enable --now docker.service
  sudo usermod -aG docker "$TARGET_USER"
}

configure_postgresql() {
  log "Initializing and enabling PostgreSQL"
  
  local needs_init=false
  if [[ ! -d "$POSTGRES_DATA_DIR" ]] || [[ -z "$(sudo ls -A "$POSTGRES_DATA_DIR" 2>/dev/null)" ]]; then
    needs_init=true
  fi

  if [[ "$needs_init" == "true" ]]; then
    sudo install -d -o postgres -g postgres -m 700 "$POSTGRES_DATA_DIR"
    sudo -u postgres initdb --locale=C.UTF-8 -E UTF8 -D "$POSTGRES_DATA_DIR"
  else
    log "PostgreSQL data directory is not empty. Skipping initialization."
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
  local fish_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d"
  local fish_nvm_config="$fish_config_dir/nvm.fish"
  [[ -r "$nvm_init" ]] || die "NVM initialization script was not found at ${nvm_init}."

  for shell_config in "$HOME/.bashrc" "$HOME/.zshrc"; do
    touch "$shell_config"
    if ! grep -Fqx "$init_line" "$shell_config"; then
      printf '\n%s\n' "$init_line" >>"$shell_config"
    fi
  done

  log "Installing the latest Node.js release through NVM"
  bash -c "source '$nvm_init'; nvm install node; nvm alias default node"

  log "Configuring Fish to use NVM's default Node.js version"
  mkdir -p "$fish_config_dir"
  printf '%s\n' \
    '# Resolve the default Node.js version installed by NVM.' \
    'if test -r /usr/share/nvm/init-nvm.sh' \
    "    set -l nvm_node (bash -c 'source /usr/share/nvm/init-nvm.sh >/dev/null 2>&1; nvm which default' 2>/dev/null)" \
    '    if test -x "$nvm_node"' \
    '        set -l nvm_bin (dirname "$nvm_node")' \
    '        if not contains -- "$nvm_bin" $PATH' \
    '            set -gx PATH "$nvm_bin" $PATH' \
    '        end' \
    '    end' \
    'end' >"$fish_nvm_config"
}

deploy_dotfiles() {
  log "Deploying dotfiles and user configurations"

  local src_dir="${SCRIPT_DIR}/dotfiles"
  [[ -d "$src_dir" ]] || die "dotfiles directory not found at ${src_dir}."

  # Create necessary home subdirectories
  mkdir -p "$HOME/.config"
  mkdir -p "$HOME/Pictures/Wallpapers"

  # Copy home level files
  for file in "$src_dir"/.bashrc "$src_dir"/.bash_profile "$src_dir"/.profile "$src_dir"/.gitconfig "$src_dir"/.zshrc "$src_dir"/.zshenv "$src_dir"/.face "$src_dir"/.face.icon "$src_dir"/autologin.conf; do
    if [[ -f "$file" ]]; then
      cp -f "$file" "$HOME/$(basename "$file")"
    fi
  done

  # Copy Pictures files
  if [[ -f "$src_dir/Pictures/memoji.png" ]]; then
    cp -f "$src_dir/Pictures/memoji.png" "$HOME/Pictures/memoji.png"
  fi
  if [[ -f "$src_dir/Pictures/Wallpapers/marvels-spider-man-miles-morales-playstation-4-playstation-5-3840x2160-4090.jpg" ]]; then
    cp -f "$src_dir/Pictures/Wallpapers/marvels-spider-man-miles-morales-playstation-4-playstation-5-3840x2160-4090.jpg" \
          "$HOME/Pictures/Wallpapers/marvels-spider-man-miles-morales-playstation-4-playstation-5-3840x2160-4090.jpg"
  fi

  # Copy all .config subfolders
  for config_item in "$src_dir"/.config/*; do
    if [[ -d "$config_item" ]]; then
      local folder_name
      folder_name="$(basename "$config_item")"
      log "Deploying config folder: $folder_name"
      mkdir -p "$HOME/.config/$folder_name"
      
      if [[ "$folder_name" == "Code" ]]; then
        mkdir -p "$HOME/.config/Code/User"
        if [[ -f "$config_item/User/settings.json" ]]; then
          cp -f "$config_item/User/settings.json" "$HOME/.config/Code/User/settings.json"
        fi
        if [[ -f "$config_item/User/keybindings.json" ]]; then
          cp -f "$config_item/User/keybindings.json" "$HOME/.config/Code/User/keybindings.json"
        fi
      elif [[ "$folder_name" == "Antigravity IDE" ]]; then
        mkdir -p "$HOME/.config/Antigravity IDE/User"
        if [[ -f "$config_item/User/settings.json" ]]; then
          cp -f "$config_item/User/settings.json" "$HOME/.config/Antigravity IDE/User/settings.json"
        fi
      elif [[ "$folder_name" == "Antigravity" ]]; then
        mkdir -p "$HOME/.config/Antigravity"
        if [[ -f "$config_item/app_storage.json" ]]; then
          cp -f "$config_item/app_storage.json" "$HOME/.config/Antigravity/app_storage.json"
        fi
      elif [[ "$folder_name" == "niri" ]]; then
        mkdir -p "$HOME/.config/niri/scripts"
        if [[ -d "$config_item/scripts" ]]; then
          cp -f "$config_item"/scripts/* "$HOME/.config/niri/scripts/"
        fi
      elif [[ "$folder_name" == "hypr" || "$folder_name" == "hypr-login" ]]; then
        # Skip copying hypr/hypr-login folders here; they are handled in configure_hypr_login
        continue
      else
        rm -rf "$HOME/.config/$folder_name"
        cp -rP "$config_item" "$HOME/.config/$folder_name"
      fi
    fi
  done

  if [[ -d "$HOME/.config/niri/scripts" ]]; then
    chmod +x "$HOME"/.config/niri/scripts/*
  fi

  # Replace hardcoded home paths /home/vishvaa with current $HOME in the copied configs and shell scripts
  log "Updating hardcoded path references to current user's home"
  find "$HOME/.config" -type f -not -path '*/.*' -exec sed -i "s|/home/vishvaa|$HOME|g" {} + 2>/dev/null || true
  if [[ -f "$HOME/.config/fish/fish_variables" ]]; then
    sed -i "s|/home/vishvaa|$HOME|g" "$HOME/.config/fish/fish_variables"
  fi
  for file in "$HOME"/.bashrc "$HOME"/.bash_profile "$HOME"/.profile "$HOME"/.zshrc "$HOME"/.zshenv; do
    if [[ -f "$file" ]]; then
      sed -i "s|/home/vishvaa|$HOME|g" "$file"
    fi
  done
}

configure_niri_hyprlock_startup() {
  local niri_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
  local niri_config="$niri_config_dir/config.kdl"
  local backup_config="$niri_config.before-hyprlogin"
  local tmp_config

  log "Ensuring Niri starts the hyprlock login screen"
  mkdir -p "$niri_config_dir"

  if [[ ! -f "$niri_config" ]]; then
    printf '%s\n' \
      '// Created by arch-dev-setup for TTY autologin with hyprlock.' \
      'spawn-at-startup "hyprlock"' >"$niri_config"
    return
  fi

  if grep -Eq '(^|[[:space:]])spawn-at-startup[[:space:]]+"hyprlock"|hyprlock' "$niri_config"; then
    return
  fi

  cp -n "$niri_config" "$backup_config"
  tmp_config="$(mktemp)"
  printf '%s\n\n' 'spawn-at-startup "hyprlock"' >"$tmp_config"
  cat "$niri_config" >>"$tmp_config"
  mv "$tmp_config" "$niri_config"
}

remove_display_managers() {
  log "Checking for and removing conflicting display managers"
  
  local dms=(
    sddm
    greetd
    gdm
    lightdm
    ly
  )

  for dm in "${dms[@]}"; do
    if pacman -Q "$dm" >/dev/null 2>&1; then
      log "Disabling service for conflicting display manager: $dm"
      sudo systemctl disable "${dm}.service" || true
      
      log "Removing display manager package: $dm"
      if ! sudo pacman -R --noconfirm "$dm" 2>/dev/null; then
        warn "Package $dm has active dependencies. Removing with nodepeps (-Rdd)..."
        sudo pacman -Rdd --noconfirm "$dm"
      fi
    fi
  done
}

configure_hypr_login() {
  log "Configuring hypr-login style TTY autologin for Niri with hyprlock"

  log "Copying hyprlock configuration..."
  local hypr_src_dir="${SCRIPT_DIR}/dotfiles/.config/hypr"
  local hypr_dest_dir="$HOME/.config/hypr"
  mkdir -p "$hypr_dest_dir"
  if [[ -f "$hypr_src_dir/hyprlock.conf" ]]; then
    cp -f "$hypr_src_dir/hyprlock.conf" "$hypr_dest_dir/hyprlock.conf"
  fi

  log "Creating lock screen avatar and wallpaper symlinks..."
  rm -f "$hypr_dest_dir/lock_avatar.png"
  ln -sf "$HOME/Pictures/memoji.png" "$hypr_dest_dir/lock_avatar.png"

  rm -f "$hypr_dest_dir/lock_wallpaper.png"
  ln -sf "$HOME/Pictures/Wallpapers/marvels-spider-man-miles-morales-playstation-4-playstation-5-3840x2160-4090.jpg" "$hypr_dest_dir/lock_wallpaper.png"

  log "Copying hyprlogin configuration..."
  local hypr_login_src_dir="${SCRIPT_DIR}/dotfiles/.config/hypr-login"
  local hypr_login_dest_dir="$HOME/.config/hypr-login"
  mkdir -p "$hypr_login_dest_dir"
  if [[ -f "$hypr_login_src_dir/install.conf" ]]; then
    cp -f "$hypr_login_src_dir/install.conf" "$hypr_login_dest_dir/install.conf"
  fi

  log "Configuring getty autologin on tty1..."
  sudo mkdir -p /etc/systemd/system/getty@tty1.service.d

  # Create autologin.conf with the current username dynamically
  sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty -o "-p -f -- \u" --noclear --autologin $TARGET_USER %I \$TERM
EOF

  log "Reloading systemd daemon..."
  sudo systemctl daemon-reload

  log "Disabling display managers (SDDM, Greetd)..."
  sudo systemctl disable sddm.service || true
  sudo systemctl disable greetd.service || true

  configure_niri_hyprlock_startup
}

print_summary() {
  cat <<EOF

Setup complete.

Installed:
  - Visual Studio Code (Microsoft build) and Antigravity IDE
  - Docker Engine, Buildx, and Compose
  - Ghostty terminal
  - Redis and redis-cli
  - PostgreSQL and pgAdmin 4 Desktop
  - GitHub CLI, hyprlock, and Microsoft Edit
  - Python, uv, Node.js through NVM, pnpm, and Bun, with Node.js available in Fish
  - Brave Browser and LocalSend

Configured:
  - User configuration dotfiles deployed and path references adjusted
  - Conflicting display managers removed (if present)
  - hypr-login style Niri setup completed (TTY autologin active on tty1)

Log out and back in before using Docker without sudo.
Authenticate GitHub CLI with: gh auth login
EOF
}

main() {
  select_aur_helper
  sudo -v
  install_repo_packages
  install_aur_helper
  remove_valkey
  install_aur_git_package antigravity-ide
  install_aur_git_package redis
  install_aur_packages
  configure_docker
  configure_postgresql
  configure_redis
  configure_nvm_and_node
  deploy_dotfiles
  remove_display_managers
  configure_hypr_login
  print_summary
}

main "$@"
