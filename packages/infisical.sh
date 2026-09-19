#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Package: Infisical CLI (install only) ───────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# On Linux we install the standalone `infisical` binary straight from the
# GitHub release (Infisical/cli), verified against the release checksums, into
# ~/.local/bin — matching how we install the VS Code CLI and devtunnel.
#
# Why not the Cloudsmith apt/rpm/apk repos anymore:
#   • Infisical has wound down the Cloudsmith-hosted package repos, and their
#     setup.deb.sh/setup.rpm.sh scripts fail on modern distros. On this box
#     (Ubuntu 26.04 aarch64) setup.deb.sh dies before configuring apt: it shells
#     out to a `python` binary (absent — Ubuntu ships only `python3`) and tries
#     `pip install distro`, which PEP 668 blocks. The repo itself only publishes
#     a single `stable` suite, so the per-codename source it writes 404s too.
#   • The GitHub release ships a proper linux_arm64 tarball (plus amd64/armv7/
#     386), so pulling it directly is architecture-correct and needs no root.
#
# Control: INFISICAL_CLI_VERSION=vX.Y.Z pins a version (default: latest).
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"
log_set_component "infisical"

if has_command infisical; then
    log_info "infisical is already installed."
    exit 0
fi

# ── macOS / Windows keep their native, self-updating package managers ───────
if os_is_macos; then
    installer_brew_install "infisical/get-cli/infisical"
    log_success "infisical installed."
    exit 0
elif os_is_windows; then
    if has_command scoop; then
        installer_scoop_install infisical
        log_success "infisical installed."
        exit 0
    fi
    log_fatal "Cannot install infisical on Windows: scoop required."
fi

# ── Linux: standalone binary from the GitHub release ────────────────────────
os_is_linux || log_fatal "Unsupported OS for infisical install."

INFISICAL_REPO="Infisical/cli"
DEST="$HOME/.local/bin/infisical"

# Map our normalized arch to the release asset's arch token.
case "${OS_ARCH_ALT}" in
    amd64) rel_arch="amd64" ;;
    arm64) rel_arch="arm64" ;;
    armhf) rel_arch="armv7" ;;
    386)   rel_arch="386"   ;;
    *)     log_fatal "Unsupported Linux architecture for infisical (${OS_ARCH})." ;;
esac

# ── Resolve the release tag (pinned via env, else the latest published) ─────
tag="${INFISICAL_CLI_VERSION:-}"
if [[ -z "$tag" ]]; then
    log_info "Resolving latest infisical CLI release..."
    tag="$(fetch_url "https://api.github.com/repos/${INFISICAL_REPO}/releases/latest" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || true)"
fi
[[ -z "$tag" ]] && log_fatal "Could not determine the infisical CLI release version."

# Tag carries a leading 'v' (v0.43.133); asset filenames use the bare number.
tag="v${tag#v}"
ver="${tag#v}"

asset="cli_${ver}_linux_${rel_arch}.tar.gz"
base_url="https://github.com/${INFISICAL_REPO}/releases/download/${tag}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

log_info "Downloading infisical CLI ${tag} (${asset})..."
if ! curl -fsSL "${base_url}/${asset}" -o "${tmp_dir}/${asset}"; then
    log_fatal "Failed to download infisical CLI from ${base_url}/${asset}"
fi

# ── Verify the download against the published checksums ─────────────────────
if ! curl -fsSL "${base_url}/checksums.txt" -o "${tmp_dir}/checksums.txt"; then
    log_fatal "Failed to download infisical checksums from ${base_url}/checksums.txt"
fi

expected="$(awk -v f="$asset" '$2 == f {print $1}' "${tmp_dir}/checksums.txt")"
[[ -z "$expected" ]] && log_fatal "No checksum for ${asset} in checksums.txt."

if has_command sha256sum; then
    actual="$(sha256sum "${tmp_dir}/${asset}" | awk '{print $1}')"
elif has_command shasum; then
    actual="$(shasum -a 256 "${tmp_dir}/${asset}" | awk '{print $1}')"
else
    log_fatal "Neither sha256sum nor shasum available to verify the download."
fi

if [[ "$actual" != "$expected" ]]; then
    log_error "Checksum mismatch for ${asset}."
    log_error "  expected: ${expected}"
    log_error "  actual:   ${actual}"
    log_fatal "Refusing to install an unverified infisical binary."
fi
log_info "Checksum verified (sha256)."

# ── Extract the `infisical` binary and install it ──────────────────────────
tar -xzf "${tmp_dir}/${asset}" -C "$tmp_dir"

extracted="$(find "$tmp_dir" -maxdepth 2 -type f -name 'infisical' | head -n 1)"
[[ -z "$extracted" ]] && log_fatal "'infisical' binary not found in ${asset}."

mkdir -p "$HOME/.local/bin"
install -m 0755 "$extracted" "$DEST"

if "$DEST" --version >/dev/null 2>&1; then
    version="$("$DEST" --version 2>/dev/null | head -n 1)"
    log_success "infisical installed (${version:-ok})."
else
    log_warn "infisical installed at $DEST but verification exited non-zero."
    log_success "infisical installed (unverified)."
fi
