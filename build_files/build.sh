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

# Brave — official RPM repo
curl -fsSLo /etc/yum.repos.d/brave-browser.repo \
  https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo

# 1Password — official RPM repo
rpm --import https://downloads.1password.com/linux/keys/1password.asc
cat > /etc/yum.repos.d/1password.repo <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

# Proton VPN — official RPM repo (per-Fedora-release URL)
fedora_release="$(rpm -E %fedora)"
curl -fsSLo "/etc/pki/rpm-gpg/RPM-GPG-KEY-protonvpn-${fedora_release}-stable" \
  "https://repo.protonvpn.com/fedora-${fedora_release}-stable/public_key.asc"
cat > /etc/yum.repos.d/protonvpn-stable.repo <<EOF
[protonvpn-fedora-stable]
name=Proton VPN Fedora Stable repository
baseurl=https://repo.protonvpn.com/fedora-${fedora_release}-stable/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-protonvpn-${fedora_release}-stable
EOF

# Claude Desktop (community-maintained RPM)
curl -fsSLo /etc/yum.repos.d/claude-desktop.repo \
  https://aaddrick.github.io/claude-desktop-debian/rpm/claude-desktop.repo

# Vivaldi — official RPM repo
rpm --import https://repo.vivaldi.com/stable/linux_signing_key.pub
cat > /etc/yum.repos.d/vivaldi.repo <<'EOF'
[vivaldi]
name=Vivaldi Stable
baseurl=https://repo.vivaldi.com/stable/rpm/$basearch
enabled=1
gpgcheck=1
gpgkey=https://repo.vivaldi.com/stable/linux_signing_key.pub
EOF

# Zen Browser — Fedora COPR
dnf5 -y copr enable sneexy/zen-browser

# Firefox needs a matching openh264 — Bazzite ships -1 but mozilla-openh264 wants -2.
# Enabling fedora-cisco-openh264 surfaces the -2 build.
dnf5 -y config-manager setopt fedora-cisco-openh264.enabled=1

# ─── Install the system layer ────────────────────────────────────────────────

dnf5 install -y \
    firefox firefox-langpacks \
    brave-browser \
    vivaldi-stable \
    1password 1password-cli \
    proton-vpn-gnome-desktop \
    claude-desktop \
    zen-browser \
    podman-compose \
    gnome-shell-extension-dash-to-panel \
    gnome-shell-extension-dash-to-dock \
    zsh

# ─── Cleanup ─────────────────────────────────────────────────────────────────
dnf5 clean all
