<h1 align="center">ShellCrash (Zero-Trust Hardened Edition)</h1>

<p align="center">
  <a target="_blank" href="https://github.com/MetaCubeX/mihomo/releases">
    <img src="https://img.shields.io/github/release/MetaCubeX/mihomo.svg?style=flat-square&label=Mihomo">
  </a>
  <a target="_blank" href="https://github.com/SagerNet/sing-box/releases">
    <img src="https://img.shields.io/github/release/SagerNet/sing-box.svg?style=flat-square&label=Sing-Box">
  </a>
  <a target="_blank" href="https://github.com/Siu-Leung/ShellCrash/commits/dev">
    <img src="https://img.shields.io/github/last-commit/Siu-Leung/ShellCrash/dev?style=flat-square&label=Dev&color=green">
  </a>
</p>

<p align="center">
  <strong>An independently maintained, zero-trust, fully self-hosted Mihomo &amp; Sing-Box manager for Linux and routers</strong>
</p>

<p align="center">
  <a href="README_CN.md">简体中文</a> | English | <a href="SECURITY_HARDENING.md">Security Audit &amp; Hardening</a> | <a href="docker/README.md">Docker Guide</a>
</p>

## Project Architecture & Branches

This project is an independently maintained, zero-trust hardened edition of ShellCrash. Every script, ruleset, dashboard, GeoData database, and compiled core binary is built and distributed directly from this repository (`Siu-Leung/ShellCrash`) with zero reliance on third-party mirrors, online subscription converters, or public relay bots.

| Branch / Path | Purpose | Contents |
| :--- | :--- | :--- |
| **`dev` branch** | Primary scripts & source branch | Installers (`install.sh`, `install_en.sh`), Shell runtime & menus (`scripts/`, `tools/`), rule templates (`rules/`), list configs (`public/`), Docker build files, and packaged `ShellCrash.tar.gz` |
| **`update` branch** | Binaries & static assets branch | Self-compiled multi-arch cores (`bin/meta/`, `bin/singbox/`, `bin/singboxr/`), Web dashboards (`bin/dashboard/`), GeoIP/GeoSite (`bin/geodata/`), full `.mrs`/`.srs` rulesets (`bin/ruleset/{mrs,srs}/`), and CA certificates |

## Key Features

- **Self-Hosted Runtime Distribution**: Removed third-party relay mirrors, online subconverter backends, public Telegram bots, external web panels, and upstream Docker images. At runtime, scripts update from `dev`, while cores, dashboards, GeoData, and all 14 rule templates are served directly from `Siu-Leung/ShellCrash@update` (upstream projects such as MetaCubeX, SagerNet, reF1nd, DustinWin, Zephyruso, and Alpine/s6 are used strictly as CI build-time inputs).
- **Zero-Leak Local Subscription Fetch & Convert**: Fetches subscriptions directly from your original URLs and converts them locally using pure POSIX `sh`/`awk`/`base64` (UTF-8 BOM stripping, streaming Base64 decode, plaintext URIs, Clash YAML, and Sing-Box JSON), with staged verification, atomic provider commit, and cached fallback on transient source failures.
- **Fail-Closed Secure Defaults**:
  - Strict TLS certificate verification (`skip_cert=OFF`) is enforced by default across the installer, HTTP libraries, core config modifiers, local converter, Telegram bot, and CI workflows.
  - Pure/Local mode (`firewall_area=4` without `public_support=ON`) binds Clash DNS, web controller, and all 4 Sing-Box inbounds strictly to `127.0.0.1`; WAN firewall rules reject external access to proxy, panel, DNS, and transparent-proxy ports.
  - Remote `bin/version` manifests are parsed strictly as whitelisted data (never sourced); script and core upgrades use staged validation with automatic rollback; config writes use `setconfig_quote` with indirect `eval`, `awk` injection, and wildcard command execution eliminated.
- **Hardened Self-Hosted Telegram Bot**: Connects strictly to `api.telegram.org`; private chats verify both `chat.id` and `from.id`, while negative group chats require an explicit `TG_ADMIN_IDS` sender allowlist (blocking unauthorized group members); uploaded backup archives are guarded against Tar-Slip and symlinks/hardlinks.
- **Broad Linux Compatibility**: Supports Mihomo (Meta), Sing-Box, and Sing-BoxR on Debian, Ubuntu, CentOS, Alpine, Arch, OpenWrt, Padavan, ASUS/Merlin, and self-built Docker containers.
- **Automated Regression CI & Supply Chain**: Least-privilege GitHub Actions workflows run automated POSIX `sh` / BusyBox `ash` syntax checks, all offline regression tests, and `ShellCrash.tar.gz` byte-parity checks on every `dev` push (`ci.yml`), while `core_easy_update` / `core_auto_update` / `bin_update` publish verified binaries, `bin/SHA256SUMS`, and refreshed `@dev`/`@update` CDN caches.

## Installation

> [!IMPORTANT]
> Run as `root`. Strict TLS certificate verification is enabled by default (only set `SKIP_CERT=1` temporarily on legacy devices missing CA root certificates).

### Standard Linux / Router

**Via jsDelivr CDN (Recommended):**

```sh
export url='https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@dev' \
  && sh -c "$(curl -fsSL $url/install_en.sh)" \
  && . /etc/profile >/dev/null 2>&1
```

**Via GitHub Raw:**

```sh
export url='https://raw.githubusercontent.com/Siu-Leung/ShellCrash/dev' \
  && sh -c "$(curl -fsSL $url/install_en.sh)" \
  && . /etc/profile >/dev/null 2>&1
```

**Via `wget`:**

```sh
export url='https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@dev' \
  && wget -q -O /tmp/install_en.sh "$url/install_en.sh" \
  && sh /tmp/install_en.sh \
  && . /etc/profile >/dev/null 2>&1
```

### Alpine Linux VM

```sh
apk add --no-cache curl wget openrc ca-certificates tzdata nftables iproute2 dcron
export url='https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@dev' \
  && sh -c "$(curl -fsSL $url/install_en.sh)" \
  && . /etc/profile >/dev/null 2>&1
```

### Docker & Offline Installation

- **Docker**: Clone the `dev` branch of this repository and build locally using `Dockerfile` and `docker/compose.yml`. See [docker/README.md](docker/README.md).
- **Offline**: Download `ShellCrash.tar.gz` from the `dev` or `update` branch, extract it on the target host, and run `init.sh`.

## Quick Start

```sh
crash        # Launch interactive management menu
crash doctor # Read-only environment & security health check
crash -h     # Show CLI help
```

### Zero-Leak Local Subscription Conversion

1. Open `6 Configuration Management -> a) Add provider` and add your original subscription URL (Clash YAML, Base64, plaintext URIs, or local file).
2. Select **`c) Fetch & convert subscriptions locally (zero-leak)`**.
3. Optionally configure exclude/include regex filters, pick a self-hosted rule template, and select `1)` to fetch, decode, filter, and assemble the final config entirely locally.
4. Scheduled task `104` (update & restart) and `105` (hot update) use the exact same zero-leak local pipeline.

### Self-Hosted Telegram Bot

1. Create your own bot token with Telegram's official `@BotFather`.
2. Configure the token and bind your personal or group ChatID under `7 Gateway & Remote -> Telegram Bot` (or notification settings).
3. All messages and control requests talk directly to `api.telegram.org` with no intermediate relay.

### Self-Building Cores & Assets

Trigger these workflows under GitHub **Actions** (`dev` branch) to keep all binaries and assets freshly built:

- `core_easy_update`: Pass `meta`, `singbox`, or `singboxr` to cross-compile from official source and push to `update`.
- `bin_update`: Refreshes Dashboards, GeoData, all `.mrs` / `.srs` rulesets (published to `bin/ruleset/{mrs,srs}/` on `update`), CA certificates, and syncs `ShellCrash.tar.gz` from `dev`.

## Development & Regression Testing

See [SECURITY_HARDENING.md](SECURITY_HARDENING.md) for the complete security audit log. After editing `scripts/`, `public/`, or `rules/`, cleanly rebuild the package and run all 15 offline regression suites:

```sh
sh sync_pkg.sh
for t in tests/test_*.sh tests/clash_geodata.sh; do sh "$t" || exit 1; done
```

## Attribution & License

This project builds independently upon the open-source ShellCrash codebase originally created by **Juewuy**, redesigned with a full security audit, zero-trust defaults, and a self-hosted supply chain. Original author copyright headers and attribution are preserved; only dependencies on upstream-hosted download mirrors, Docker images, and third-party relay services have been removed.

Licensed under the [GNU General Public License v3.0](LICENSE.txt).
