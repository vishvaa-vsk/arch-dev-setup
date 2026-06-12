# Arch Dev Setup

An idempotent development-machine installer for current Arch Linux and CachyOS
installations.

## Install

Run the script as your normal user:

```bash
cd ~/arch-dev-setup
./setup.sh
```

The script performs a full system upgrade, installs repository and AUR packages,
enables Docker, PostgreSQL, and Redis, initializes PostgreSQL when necessary,
and installs the latest Node.js release through NVM.

## Package Sources

Official repositories:

- Docker Engine, Buildx, Compose, GitHub CLI, PostgreSQL, Python, NVM, pnpm,
  Bun, uv, and Microsoft Edit (`msedit`)

AUR:

- [Antigravity](https://aur.archlinux.org/antigravity.git), built directly from
  its AUR Git repository
- [Visual Studio Code](https://aur.archlinux.org/packages/visual-studio-code-bin)
- [Redis](https://aur.archlinux.org/redis.git), built directly from its AUR Git
  repository because it may be absent from AUR helper search results
- [pgAdmin 4 Desktop](https://aur.archlinux.org/packages/pgadmin4-desktop)
- [Brave Browser](https://aur.archlinux.org/packages/brave-bin)
- [LocalSend](https://aur.archlinux.org/packages/localsend-bin)

On CachyOS, packages such as Brave may come from a configured CachyOS
repository instead of being built from AUR.

## Notes

- Run this only on Arch Linux or an Arch-based distribution.
- Do not run it as root. It uses `sudo` where required.
- The script uses actual Redis, not Valkey. Redis supplies both `redis-server`
  and `redis-cli`. If Valkey is installed, the script removes it before
  installing Redis.
- Log out and back in after installation so Docker group membership takes
  effect.
- NVM is initialized in both `~/.bashrc` and `~/.zshrc`.
- Re-running the script upgrades the system and skips packages already
  installed.
