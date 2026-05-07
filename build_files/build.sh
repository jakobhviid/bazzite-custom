#!/bin/bash
# Image build steps that run inside the Containerfile RUN. Adds third-party
# RPM repos, enables Fedora's cisco-openh264 (needed by mozilla-openh264 which
# Firefox depends on), and layers all browsers + 1Password + the GNOME
# extensions and tools we want present on every machine.
#
# The set here mirrors RPM_PACKAGES in
# /var/home/jakob/Developer/ReinstallScripts/Linux/install-bazzite.sh
# plus firefox + vivaldi (which install-bazzite.sh doesn't carry today).
# Once this image is in use, those entries can be dropped from RPM_PACKAGES.

set -ouex pipefail

# ─── Third-party repos ────────────────────────────────────────────────────────
#
# Canonical Fedora pattern: GPG keys go on disk at /etc/pki/rpm-gpg/RPM-GPG-KEY-<name>
# (mode 0644) and the .repo file references them via gpgkey=file:///… . With
# repo_gpgcheck=1, the key must be present BEFORE the next metadata refresh,
# otherwise dnf5 emits "repomd.xml GPG signature verification error: Signing
# key not found" and silently falls back. Fetching the key to a remote URL
# in gpgkey= works for gpgcheck=1 (DNF auto-imports on first install) but is
# racy under repo_gpgcheck=1.

# Brave — official RPM repo + official key
curl -fsSLo /etc/pki/rpm-gpg/RPM-GPG-KEY-brave-browser \
  https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
chmod 0644 /etc/pki/rpm-gpg/RPM-GPG-KEY-brave-browser
cat > /etc/yum.repos.d/brave-browser.repo <<'EOF'
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/x86_64/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-brave-browser
EOF

# 1Password — official RPM repo + official key
curl -fsSLo /etc/pki/rpm-gpg/RPM-GPG-KEY-1password \
  https://downloads.1password.com/linux/keys/1password.asc
chmod 0644 /etc/pki/rpm-gpg/RPM-GPG-KEY-1password
cat > /etc/yum.repos.d/1password.repo <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-1password
EOF
# repo_gpgcheck disabled deliberately. Upstream's official template sets it to
# 1, but dnf5 has a known race (issue tracked, fix in 5.2.12+) where the key
# isn't found in the keyring on first refresh — even with the canonical
# file:///etc/pki/rpm-gpg/ pattern. Once F44's dnf5 picks up the fix, flip back
# to 1. Package-level gpgcheck=1 continues to verify each RPM against this key,
# which is the security-critical check; repo_gpgcheck only adds metadata-fetch
# integrity, already covered by HTTPS+TLS to downloads.1password.com.

# Proton VPN deliberately NOT in the image — its proton-vpn-daemon RPM ships a
# %posttrans scriptlet that calls systemctl, which fails in a build container
# (no systemd PID 1) and kills the whole dnf5 transaction. Stays layered via
# ReinstallScripts/Linux/install-bazzite.sh on the live system, where systemd
# is running and the scriptlet succeeds.

# Claude Desktop (community-maintained RPM). Their upstream .repo enables
# repo_gpgcheck=1 with a remote gpgkey URL, which trips the same dnf5 race
# as 1Password. Fetch their key to disk and write our own .repo with
# repo_gpgcheck=0; gpgcheck=1 still verifies each RPM against the key.
curl -fsSLo /etc/pki/rpm-gpg/RPM-GPG-KEY-claude-desktop \
  https://pkg.claude-desktop-debian.dev/KEY.gpg
chmod 0644 /etc/pki/rpm-gpg/RPM-GPG-KEY-claude-desktop
cat > /etc/yum.repos.d/claude-desktop.repo <<'EOF'
[claude-desktop]
name=Claude Desktop for Fedora/RHEL
baseurl=https://pkg.claude-desktop-debian.dev/rpm/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-claude-desktop
metadata_expire=1h
EOF

# Vivaldi — official RPM repo + official key
curl -fsSLo /etc/pki/rpm-gpg/RPM-GPG-KEY-vivaldi \
  https://repo.vivaldi.com/stable/linux_signing_key.pub
chmod 0644 /etc/pki/rpm-gpg/RPM-GPG-KEY-vivaldi
cat > /etc/yum.repos.d/vivaldi.repo <<'EOF'
[vivaldi]
name=Vivaldi Stable
baseurl=https://repo.vivaldi.com/stable/rpm/$basearch
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-vivaldi
EOF

# Zen Browser — Fedora COPR (the dnf5 copr plugin handles its own key + repo file)
dnf5 -y copr enable sneexy/zen-browser

# Atim's COPRs — well-maintained third-party COPR for tools not in main Fedora.
dnf5 -y copr enable atim/starship
dnf5 -y copr enable atim/lazygit

# Firefox needs a matching openh264 — Bazzite ships -1 but mozilla-openh264 wants -2.
# Enabling fedora-cisco-openh264 surfaces the -2 build.
dnf5 -y config-manager setopt fedora-cisco-openh264.enabled=1

# ─── Install the system layer ────────────────────────────────────────────────

dnf5 install -y \
    firefox firefox-langpacks \
    brave-browser \
    vivaldi-stable \
    1password 1password-cli \
    claude-desktop \
    zen-browser \
    podman-compose \
    gnome-shell-extension-dash-to-panel \
    gnome-shell-extension-dash-to-dock \
    zsh \
    zsh-autosuggestions zsh-syntax-highlighting \
    bat btop butane eza fzf htop jq just tmux zoxide \
    starship lazygit \
    nerd-fonts \
    libheif-tools \
    unrar 7zip \
    gnome-tweaks

# ─── Enable image-shipped system services ────────────────────────────────────
# The system-preset file at /usr/lib/systemd/system-preset/90-bazzite-custom.preset
# would also handle this on an installed system, but presets aren't auto-applied
# in the build container — explicit enable creates the symlink at build time so
# the service runs on first boot.
systemctl enable bazzite-custom-flatpaks.service

# ─── Cleanup ─────────────────────────────────────────────────────────────────
dnf5 clean all
# /run is a runtime-only tmpfs on the live system; bootc lint flags any content
# left there at build time. dnf leaves a state dir behind even after clean all.
rm -rf /run/dnf
# /var/lib/dnf/repos/ accumulates per-repo cache directories (with hash
# suffixes) and a 'countme' file from dnf's anonymous opt-in counter. We
# don't run dnf on the live system (bootc-managed), so the cache is dead
# weight AND triggers bootc lint var-tmpfiles warnings. /var/lib/dnf itself
# stays — dnf's transaction history (history.sqlite, etc.) is part of normal
# install state and is declared in usr/lib/tmpfiles.d/bazzite-custom.conf.
rm -rf /var/lib/dnf/repos
