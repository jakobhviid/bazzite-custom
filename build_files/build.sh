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

# 1Password deliberately NOT in the image — its install model is per-user
# (the RPM %post adds the live user to the onepassword group; no live user
# exists in a build container). We tried baking it (pinned GIDs, sysusers.d,
# manual usermod plumbing) and the IPC group check still rejected browser
# extension connections on rebased machines. Switched to brew cask
# `ublue-os/tap/1password-gui-linux` on the userspace side instead — the
# uBlue tap automates setgid + native messaging manifests + custom_allowed_browsers
# via PR #296 (merged 2026-04-05), and runs as the live user so per-user
# group setup just works. The CLI (`op`) is dropped — was nice-to-have, not
# needed.

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

# ─── Pull canonical configs from ReinstallScripts ────────────────────────────
# These two files live in jakobhviid/ReinstallScripts as the editable source
# of truth (they also need to be on stock Bazzite for `just brave` testing
# and for any per-user wireplumber overrides). Fetching at image build time
# means: change the policy in ReinstallScripts → push → next image build
# picks it up automatically, no manual sync between repos. Path contract:
# don't move these files in ReinstallScripts without updating these URLs.
RS_RAW="https://raw.githubusercontent.com/jakobhviid/ReinstallScripts/main"

mkdir -p /etc/brave/policies/managed
curl -fsSLo /etc/brave/policies/managed/brave-policy.json \
    "${RS_RAW}/Linux/assets/brave-policy.json"

mkdir -p /usr/share/wireplumber/wireplumber.conf.d
curl -fsSLo /usr/share/wireplumber/wireplumber.conf.d/rename-devices.conf \
    "${RS_RAW}/Linux/assets/rename-devices.conf"

# ─── Install the system layer ────────────────────────────────────────────────

dnf5 install -y \
    firefox firefox-langpacks \
    brave-browser \
    vivaldi-stable \
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
    rsms-inter-fonts \
    jetbrains-mono-fonts \
    cascadia-code-fonts cascadia-code-nf-fonts \
    google-roboto-fonts google-roboto-mono-fonts \
    dejavu-sans-fonts dejavu-serif-fonts dejavu-sans-mono-fonts \
    libheif-tools \
    unrar 7zip \
    gnome-tweaks

# ─── Remove base image packages we don't want ────────────────────────────────
# bazzite-gnome ships kmod-openrazer + openrazer-kmod-common for users who
# want RGB/DPI control via polychromatic. The razeraccessory kernel driver
# matches every Razer mouse PID and tells usbhid to mark the secondary HID
# interfaces ("skipping secondary interface" in dmesg) — which are exactly
# the keyboard endpoints Razer mice use to replay onboard macros. Result:
# keystrokes configured via Synapse on macOS/Windows (stored in the mouse's
# onboard memory) silently fail on Linux even though they work natively on
# the original host with zero software. The mouse firmware is correct; the
# Linux host driver is hijacking interfaces it shouldn't.
#
# Users who actively want polychromatic features can layer the kernel module
# with `rpm-ostree install kmod-openrazer openrazer-kmod-common` + reboot.
# Default for everyone else: Razer mice with onboard profiles just work.
dnf5 remove -y kmod-openrazer openrazer-kmod-common

# ─── Refresh icon cache so newly-installed apps' icons resolve ──────────────
# Some packages (notably zen-browser) install icons under /usr/share/icons/
# hicolor/ but don't run gtk-update-icon-cache in their %post scriptlet.
# Result on the live system: the .desktop file has Icon=zen-browser, the PNG
# files exist at /usr/share/icons/hicolor/<size>/apps/zen-browser.png, but
# the cache (icon-theme.cache) doesn't list zen-browser entries — so GTK's
# IconTheme.has_icon("zen-browser") returns False and apps fall back to the
# generic application icon. Forcing a cache rebuild here ensures the image
# ships a complete cache that includes all newly-installed apps.
gtk-update-icon-cache --force /usr/share/icons/hicolor

# ─── Vivaldi codec relocation ────────────────────────────────────────────────
# Vivaldi can't legally bundle proprietary H.264/AAC codecs. Their RPM ships an
# update-ffmpeg downloader and the post-install scriptlet runs it, landing the
# library at /var/opt/vivaldi/media-codecs-<ver>/libffmpeg.so.
#
# /var on bootc is per-deployment runtime state: image content in /var copies
# to the live system on first install only, then is preserved across upgrades.
# Keeping the codec there means a Vivaldi-version bump in our image would
# update the binary in /opt (immutable layer) but NOT the codec in /var —
# version skew, possibly breaking playback or crashing on ABI mismatch.
#
# Move the library to /opt/vivaldi/lib/ — one of Vivaldi's documented
# system-wide search paths (per its update-ffmpeg script). Now the codec is
# part of the immutable layer and updates atomically with the binary on every
# rebase. Side effect: the bootc lint var-tmpfiles warning for the file goes
# away because /var/opt/vivaldi no longer exists in the image.
#
# If a user later runs Vivaldi's own update-ffmpeg to fetch a newer codec,
# /opt/vivaldi/lib/ is read-only on the live system → it'll fall back to
# ~/.local/lib/vivaldi/ (per-user) and that copy takes precedence over ours.
# Acceptable: image-shipped is the default; user can always override.
# Vivaldi's RPM creates BOTH a versioned symlink (media-codecs-X.Y) AND the
# real directory it points to (media-codecs-git-DATE), each containing a
# libffmpeg.so. A naive `cp /var/opt/vivaldi/media-codecs-*/libffmpeg.so`
# expands to two paths that both resolve to the same physical file → cp
# refuses with "will not overwrite just-created". `find -type f` filters
# down to the real file(s) only; `head -1` picks one if multiple exist.
ffmpeg_src=$(find /var/opt/vivaldi -path '*/media-codecs-*/libffmpeg.so' -type f 2>/dev/null | head -1)
if [[ -n "$ffmpeg_src" ]]; then
    mkdir -p /opt/vivaldi/lib
    cp "$ffmpeg_src" /opt/vivaldi/lib/
    rm -rf /var/opt/vivaldi
fi

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
