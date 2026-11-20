<h1 align="center">ShellCrash (Zero-Trust Hardened Edition)</h1>

<p align="center">
  <a target="_blank" href="https://github.com/MetaCubeX/mihomo/releases">
    <img src="https://img.shields.io/github/release/MetaCubeX/mihomo.svg?style=flat-square&label=Core">
  </a>
  <a target="_blank" href="https://github.com/Siu-Leung/ShellCrash/releases">
    <img src="https://img.shields.io/github/release/Siu-Leung/ShellCrash.svg?style=flat-square&label=ShellCrash&colorB=green">
  </a>
</p>

<p align="center">
  <strong>A clean, self-hosted, zero-trust Mihomo / Sing-Box proxy manager for Linux and routers</strong>
</p>

<p align="center">
  <a href="README_CN.md">简体中文</a> | English | <a href="SECURITY_HARDENING.md">Security Hardening Audit</a>
</p>

## Key Features

- **Zero-Trust & No Third-Party Relays**: Removed third-party relay mirrors, online subconverter backends, public Telegram bots, external web panels, and promotional links. All scripts, rules, dashboards, GeoData, and cores are served from this repository (`dev` branch for scripts, `update` branch for self-built binaries).
- **Zero-Leak Local Subscription Fetch & Convert**: Fetches subscriptions directly from your original URLs and converts them locally using pure POSIX `sh`/`awk`/`base64` (auto-detecting Base64, plaintext URI lists, Clash YAML, and Sing-Box JSON), generating pure local `type: file` / `type: local` provider configs with regex filtering.
- **Secure Defaults**: TLS certificate verification is enforced by default across the installer, downloader, core configs, and Telegram bot; Pure/Local mode (`firewall_area=4`) binds exclusively to `127.0.0.1` unless `public_support=ON` is explicitly enabled; config writes are atomic and injection-safe with indirect `eval` eliminated.
- **Broad Linux Compatibility**: Supports Mihomo (Meta), Sing-Box, and Sing-BoxR on Debian, Ubuntu, CentOS, Alpine, Arch, OpenWrt, Padavan, ASUS/Merlin, and Docker.
- **Self-Hosted Binary Supply Chain**: Built-in GitHub Actions workflows (with concurrency locking and rebase-retry push) cross-compile all architectures directly from upstream `MetaCubeX/mihomo`, `SagerNet/sing-box`, and `reF1nd/sing-box` into your `update` branch.

## Installation

> [!IMPORTANT]
> Run as `root`. Strict TLS certificate verification is enabled by default (only set `SKIP_CERT=1` temporarily on legacy devices missing CA certificates).

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

- **Docker**: Build directly from the `docker/` directory in this repository.
- **Offline**: Download `ShellCrash.tar.gz` from the `dev` or `update` branch, extract it on the target host, and run `init.sh`.

## Quick Start

```sh
crash        # Launch interactive menu
crash doctor # Read-only environment & security health check
crash -h     # Show CLI help
```

### Zero-Leak Local Subscription Conversion

1. Open `6 Configuration Management -> a) Add provider` and add your subscription URL (Clash YAML, Base64, plaintext URIs, or local file).
2. Select **`c) Fetch & convert subscriptions locally (zero-leak)`**.
3. Optionally configure exclude/include regex filters, choose a rule template, and select `1)` to fetch, decode, filter, and assemble the final config entirely on your machine.
4. Scheduled task `104` (update & restart) and `105` (hot update) automatically use the same zero-leak local pipeline.

### Self-Building Cores & Assets

Trigger these workflows under GitHub **Actions** to replace all binaries with your own clean builds:

- `core_easy_update`: Pass `meta`, `singbox`, or `singboxr` to compile from official source and push to `update`.
- `bin_update`: Refreshes Dashboards, GeoData/ruleset archives, CA certificates, and syncs `ShellCrash.tar.gz` from `dev`.

## Development & Regression Testing

See [SECURITY_HARDENING.md](SECURITY_HARDENING.md) for the complete audit log. After editing `scripts/` or `public/`, rebuild the package and run all offline regression tests:

```sh
sh sync_pkg.sh
for t in tests/test_*.sh; do sh "$t"; done
```

## License

Licensed under the [GNU General Public License v3.0](LICENSE.txt).
