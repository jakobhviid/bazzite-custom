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
repo_gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-1password
EOF

# Proton VPN deliberately NOT in the image — its proton-vpn-daemon RPM ships a
# %posttrans scriptlet that calls systemctl, which fails in a build container
# (no systemd PID 1) and kills the whole dnf5 transaction. Stays layered via
# ReinstallScripts/Linux/install-bazzite.sh on the live system, where systemd
# is running and the scriptlet succeeds.

# Claude Desktop (community-maintained RPM — no GPG signing upstream)
curl -fsSLo /etc/yum.repos.d/claude-desktop.repo \
  https://aaddrick.github.io/claude-desktop-debian/rpm/claude-desktop.repo

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
    zsh

# ─── Cleanup ─────────────────────────────────────────────────────────────────
dnf5 clean all
# /run is a runtime-only tmpfs on the live system; bootc lint flags any content
# left there at build time. dnf leaves a state dir behind even after clean all.
rm -rf /run/dnf
