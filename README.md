# bazzite-custom

A small ublue/Bazzite derivative for Jakob's three-machine GNOME fleet. Two image variants built in parallel from one Containerfile:

| Image | Base | Target machines |
|---|---|---|
| `ghcr.io/jakobhviid/bazzite-custom:latest` | `ghcr.io/ublue-os/bazzite-gnome:stable` | X1 Carbon Gen 13 (Intel only) |
| `ghcr.io/jakobhviid/bazzite-nvidia-custom:latest` | `ghcr.io/ublue-os/bazzite-gnome-nvidia-open:stable` | NVIDIA RTX 20-series and newer (Turing+, including RTX 30/40/50) |

Both signed with cosign. The build runs daily at 10:00 UTC (12:00 CEST). Every daily run pulls the current Bazzite base **and** refreshes layered RPMs (browsers, COPRs) against their upstream repos, so layered packages stay ≤24h behind their own upstream releases.

## Where the build lives

Built on a homelab host (Fedora CoreOS, 14-core / 62 GB RAM) rather than via GitHub Actions. The original GHA workflow was 5–8× slower on `ubuntu-24.04` runners *and* intermittently failed at the `free-disk-space` step before the rechunked OCI image was assembled — disk-space was the bottleneck, not the build itself. Moving to the homelab made the daily build deterministic.

The build sources (Containerfile, install scripts, system_files tree, cosign config) live in a separate private repo. This public repo carries the rebase instructions, the cosign public key for verification, and the documentation of what's in the image — i.e. everything a consumer of the image needs. Same daily cadence, same artifact on GHCR, same cosign-signed manifest.

## Rebase a machine

Two paths: an automated one-liner via the [ReinstallScripts](https://github.com/jakobhviid/ReinstallScripts) repo (handles cosign trust setup, signed rebase, optional package layering, and reboot in one shot), or a manual two-step using just `rpm-ostree`.

**Why the manual path is two steps:** `rpm-ostree`'s signed verifier needs three things on disk before it can verify a rebase target — the cosign public key at `/etc/pki/containers/bazzite-custom.pub`, a trust rule in `/etc/containers/policy.json`, and a `/etc/containers/registries.d/` entry. None of these exist on stock Bazzite for our image. The pub key ships *inside* our image, so it's only present after the first rebase has already happened. The two-step pattern (`ostree-unverified-image:` first to bootstrap the key onto disk, then `ostree-image-signed:` for ongoing verification) sidesteps the chicken-and-egg. The automated script does the same dance + writes the policy.json + registries.d entries for you, so you can go straight to `ostree-image-signed:`.

### Intel-only laptop (X1 Carbon Gen 13, Intel-only hardware)

**Automated (recommended):**

```bash
git clone https://github.com/jakobhviid/ReinstallScripts.git
cd ReinstallScripts
./Linux/install-bazzite.sh <machine_name>
# Detects stock Bazzite, sets up trust, rebases signed, reboots.
# After reboot, run the same command again — it'll detect the image and
# do userspace setup (brew bundle, GNOME extensions, dotfiles, etc.).
```

**Manual:**

```bash
sudo rpm-ostree rebase ostree-unverified-image:registry:ghcr.io/jakobhviid/bazzite-custom:latest
sudo systemctl reboot

# After the first boot of the new image — optionally promote to signed
# (the cosign pub key is now on disk; you'll still need to add a
# /etc/containers/policy.json trust rule, see ublue docs for the exact JSON)
sudo rpm-ostree rebase ostree-image-signed:registry:ghcr.io/jakobhviid/bazzite-custom:latest
```

### NVIDIA desktop (RTX 20-series and newer)

Requires NVIDIA Turing or later (RTX 20/30/40/50) for the open kernel module. RTX 16-series and older need the proprietary closed driver — use `bazzite-gnome-nvidia` upstream as your base, not this image.

**Automated (recommended):**

```bash
git clone https://github.com/jakobhviid/ReinstallScripts.git
cd ReinstallScripts
./Linux/install-bazzite.sh <machine_name>
# Same flow as the laptop — auto-detects this is NVIDIA hardware (or
# is told via the machine name) and rebases to bazzite-nvidia-custom.
```

**Manual:**

```bash
sudo rpm-ostree rebase ostree-unverified-image:registry:ghcr.io/jakobhviid/bazzite-nvidia-custom:latest
sudo systemctl reboot

# After the first boot of the new image — optionally promote to signed
sudo rpm-ostree rebase ostree-image-signed:registry:ghcr.io/jakobhviid/bazzite-nvidia-custom:latest
```

### Subsequent updates (both variants)

`sudo bootc upgrade` (or `sudo rpm-ostree upgrade`) — pulls the latest image, verifies the cosign signature (if rebased signed), stages, applies on next reboot.

### Fresh installs

There is no first-party install ISO for this image. To flatten a machine: install **stock Bazzite GNOME** from upstream's installer, then rebase using the steps above (or run `install-bazzite.sh` from [ReinstallScripts](https://github.com/jakobhviid/ReinstallScripts) which automates trust + rebase + post-install).

---

## What's baked in

**RPMs from Fedora F44 main:** firefox, firefox-langpacks, vivaldi-stable, claude-desktop, zen-browser, podman-compose, gnome-shell-extension-{dash-to-panel,dash-to-dock}, zsh, bat, btop, butane, eza, fzf, htop, jq, just, tmux, zoxide, zsh-autosuggestions, zsh-syntax-highlighting, libheif-tools, unrar, 7zip, gnome-tweaks, nerd-fonts, rsms-inter-fonts, jetbrains-mono-fonts, cascadia-code-{,nf-}fonts, google-roboto-{,mono-}fonts, dejavu-{sans,serif,sans-mono}-fonts.

**RPMs from custom repos:** brave-origin (`brave-browser-rpm-release.s3` — same Brave repo as standard Brave, different package), vivaldi (repo.vivaldi.com), claude-desktop (aaddrick.github.io community repo), zen-browser (Fedora COPR `sneexy/zen-browser`), starship + lazygit (`atim/starship`, `atim/lazygit` COPRs), ghostty (`scottames/ghostty` COPR — recommended by Ghostty's own install docs; ships `gtk4-layer-shell` as a sibling dep from the same repo), Cider (repo.cider.sh, Cider Collective).

**Proton suite (Mail, Pass, Bridge, Meet, Authenticator):** fetched as direct `.rpm` downloads from `proton.me` at image build time (Proton publishes no yum repo for these). Mail tracks Proton's EarlyAccess channel; the rest track Stable. Proton VPN is intentionally excluded — see "What's NOT in the image" below.

**System config files:**

- `/etc/brave/policies/managed/brave-policy.json` — Brave Origin hardening + Qwant default search. Trimmed for Origin (drops keys whose features are compiled out of the Origin binary: Wallet/Rewards/Leo/Tor/News/Talk/VPN/Playlist/Speedreader/Wayback/P3A/Web Discovery/Stats Ping/IPFS). Mirrored at [ReinstallScripts/Linux/assets/brave-origin-policy.json](https://github.com/jakobhviid/ReinstallScripts/blob/main/Linux/assets/brave-origin-policy.json) where `just drift` keeps the two in sync.
- `/etc/xdg/mimeapps.list` — Brave Origin as system default browser (per-user override still wins).
- `/etc/pki/containers/bazzite-custom.pub` — cosign public key for client-side update verification.
- `/usr/share/wireplumber/wireplumber.conf.d/rename-devices.conf` — friendly names for Sonos Ace + Sennheiser BTD 700 (no-op when those devices aren't connected). Same dual-home setup as the Brave policy: source-of-truth in the build repo, copy in ReinstallScripts for stock-Bazzite use.

**System services baked in:**

- `/usr/lib/systemd/system/bazzite-custom-flatpaks.service` — runs `flatpak preinstall -y --noninteractive` on boot, applies the file at `/usr/share/flatpak/preinstall.d/bazzite-custom.preinstall` (33 Flathub apps). Auto-enabled via `/usr/lib/systemd/system-preset/90-bazzite-custom.preset`.
- `/usr/lib/systemd/user/{brave-origin,vivaldi,nextcloud}-unlock.service` — drops stale singleton-lock files at user login so the apps don't refuse to launch after crashes. Auto-enabled per-user via `/usr/lib/systemd/user-preset/90-bazzite-custom.preset`.

---

## What's NOT in the image (and why)

**Per-user state** — handled by [ReinstallScripts](https://github.com/jakobhviid/ReinstallScripts) (when run) or stays the user's responsibility:

- `Brewfile.<machine>` userspace (formulae, casks, Flatpaks via brew bundle)
- 6 GNOME extensions installed via `gext` (`tilingshell`, `copyous`, `hide-minimized`, `quick-settings-audio-panel`, `quicksettings-audio-devices-renamer`, `CoverflowAltTab`) — none are packaged as RPMs in any major repo
- All dconf snapshots (gnome-shell, Ptyxis), `.desktop` overrides + custom icons, autostart entries, PWAs
- Templated shell config (`.zshrc`, `starship.toml`, `tmux.conf`, git identity)

**Per-machine state**:

- `assets/speaker-eq.conf` — explicitly X1 Carbon-only (header says so)
- Any other audio-device-rule for hardware not in `wireplumber.conf.d/rename-devices.conf`

**Deferred for technical reasons**:

- **`proton-vpn-gnome-desktop`** — its `proton-vpn-daemon` RPM ships a `%posttrans` scriptlet that calls `systemctl` to enable a service. In a build container there's no systemd PID 1, the scriptlet exits 1, and the **entire** `dnf5` transaction aborts (every other package in the same `dnf5 install` line vanishes too — initial debugging is misleading because the failure is reported far from the offending package). Stays in `RPM_PACKAGES` of `install-bazzite.sh` where it works on a live system.
- **`p7zip`** — replaced by `7zip` (modern Igor Pavlov port, in main F44).

**Stays in brew (intentional)**:

- `claude-code` — updates multiple times a week; brew gives same-day pickup vs the image's daily rebuild. Note: `claude-desktop` (the GUI) IS in the image; `claude-code` (the CLI) is the brew one.
- `dotnet` — niche language runtime; if you don't actively do .NET work this is dead weight.
- `typst`, `sesh`, `fzf-tab`, `zsh-autopair`, `zsh-completions`, `zsh-history-substring-search`, `zsh-you-should-use` — no Fedora/COPR packaging; would need `git clone` or `cargo install` patterns we deliberately avoid in the image.
- The 3 patched Nerd Font typefaces (FiraCode-NF, Hack-NF, MesloLG-NF) — only the `nerd-fonts` symbols-only equivalent is in F44; the patched typefaces would need GitHub-release tarballs.
- All other Flatpaks not in the `bazzite-custom.preinstall` list — handled per-machine via brew bundle.

---

## Gotchas you may hit as a user of this image

### `/opt` is part of the immutable image layer — don't layer `/opt`-using RPMs

Atomic Fedora ships `/opt → /var/opt` so users can write to it on the live system. RPMs that install into `/opt` (Brave, Vivaldi, Claude Desktop) fail to unpack against that symlink with `cpio: mkdir failed - File exists`. Our image replaces `/opt` with a real directory in the Containerfile so the bundled apps install cleanly and version with the OS.

**Consequence**: `rpm-ostree install <pkg>` on top of this image will SILENTLY drop any `/opt` payload from the layered RPM. The new deployment commits with whatever the package put in `/usr/bin` (typically symlinks like `/usr/bin/1password → /opt/1Password/1password`), but the actual `/opt` files don't materialize because `/opt` is part of the read-only composefs root, not the per-deployment writable `/var/opt`. Symptom: dead symlink under `/usr/bin`, no app icon in GNOME, "command not found" when running.

**Rule**: don't layer `/opt`-using RPMs on this image. Install via brew (writes to `/home/linuxbrew`, which IS writable) or ask for it to be baked into the image at build time. Single-file `/usr/bin` packages (e.g. `1password-cli`'s `op`) layer fine.

### Flatpak preinstalls respect user uninstalls

The 33 Flathub apps under `/usr/share/flatpak/preinstall.d/bazzite-custom.preinstall` are installed on first boot via Fedora's native `flatpak-preinstall` mechanism. Per `man flatpak-preinstall`: *"Users can opt out of preinstalled flatpaks by simply uninstalling them, at which point they won't get automatically reinstalled again."* Flatpak tracks per-app what it preinstalled, so a `flatpak uninstall` is permanent — it survives image rebuilds.

### GNOME Boxes is RPM, not Flatpak (deliberately)

Boxes is the only GUI app in the image baked as an RPM despite having a Flathub build. The Flatpak sandbox can't expose `/dev/dri/*` and the virgl pipeline to QEMU cleanly enough for `virtio-vga-gl` to engage — every guest falls back to `llvmpipe` (software rendering), unusable for modern desktops. The RPM has full host GPU access. Five RPMs ship together for this: `gnome-boxes`, `libvirt-daemon-kvm`, `virglrenderer`, `swtpm`, `edk2-ovmf`.

Boxes uses `qemu:///session` (per-user libvirt daemon, on-demand via user-bus socket) — zero post-rebase plumbing. If you want `virt-manager` (system mode), layer it via `rpm-ostree install` and do the libvirt group setup on the live system.

**Flatpak-to-RPM migration**: removing `org.gnome.Boxes` from `bazzite-custom.preinstall` only stops new installs (per `flatpak-preinstall`'s additive semantics). Machines that already received the Flatpak keep it after rebase — they'll see two "Boxes" entries in the launcher, both reading the same VM XMLs. One-time fix: `flatpak uninstall org.gnome.Boxes`.

---

## Verification

Manually verify a published image with the cosign public key in this repo:

```bash
cosign verify --key cosign.pub ghcr.io/jakobhviid/bazzite-custom:latest
cosign verify --key cosign.pub ghcr.io/jakobhviid/bazzite-nvidia-custom:latest
```

On a rebased machine, `rpm-ostree`/`bootc` verifies signatures automatically against `/etc/pki/containers/bazzite-custom.pub` (baked into the image; same key as `cosign.pub` here).

## Cosign

- Algorithm: ECDSA P-256 (cosign default).
- Passphrase-encrypted private key.
- Public key committed at [`cosign.pub`](cosign.pub) and baked into the image at `/etc/pki/containers/bazzite-custom.pub` — same key, two locations for ergonomics (manual `cosign verify` vs in-image `rpm-ostree`/`bootc` verification).

---

## Upstream template attribution

This repo was forked from [ublue-os/image-template](https://github.com/ublue-os/image-template). The bootc/rpm-ostree mechanics and the cosign signing setup follow ublue's published patterns; the customizations above are this fleet's.

Useful upstream resources:

- [Universal Blue Forums](https://universal-blue.discourse.group/)
- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc discussion forums](https://github.com/bootc-dev/bootc/discussions)
