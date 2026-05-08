# bazzite-custom

A small ublue/Bazzite derivative for Jakob's three-machine GNOME fleet. Forked from [ublue-os/image-template](https://github.com/ublue-os/image-template); the original template README is preserved at the bottom of this file under [Upstream template notes](#upstream-template-notes).

Two image variants built in parallel from one Containerfile via a GHA matrix:

| Image | Base | Target machines |
|---|---|---|
| `ghcr.io/jakobhviid/bazzite-custom:latest` | `ghcr.io/ublue-os/bazzite-gnome:stable` | X1 Carbon Gen 13 (Intel only) |
| `ghcr.io/jakobhviid/bazzite-nvidia-custom:latest` | `ghcr.io/ublue-os/bazzite-gnome-nvidia-open:stable` | NVIDIA RTX 20-series and newer (Turing+, including RTX 30/40/50) |

Both signed with cosign. The build runs on every push to `main` and polls upstream Bazzite every 3 hours — it only rebuilds when the upstream `:stable` digest has actually changed (see [Build pipeline](#build-pipeline) below for the digest-gated polling mechanism).

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

There is no first-party install ISO for this image. To flatten a machine: install **stock Bazzite GNOME** from upstream's installer, then rebase using the steps above (or run `install-bazzite.sh` from [ReinstallScripts](https://github.com/jakobhviid/ReinstallScripts) which automates trust + rebase + post-install). The `Build disk images` workflow (`.github/workflows/build-disk.yml`) is checked in but disabled — see the long comment in that file for the bib-vs-Bazzite-base depsolve incompatibility blocking it.

---

## What's baked in

**RPMs from Fedora F44 main:** firefox, firefox-langpacks, brave-browser, vivaldi-stable, claude-desktop, zen-browser, podman-compose, gnome-shell-extension-{dash-to-panel,dash-to-dock}, zsh, bat, btop, butane, eza, fzf, htop, jq, just, tmux, zoxide, zsh-autosuggestions, zsh-syntax-highlighting, libheif-tools, unrar, 7zip, gnome-tweaks, nerd-fonts, rsms-inter-fonts, jetbrains-mono-fonts, cascadia-code-{,nf-}fonts, google-roboto-{,mono-}fonts, dejavu-{sans,serif,sans-mono}-fonts.

**RPMs from custom repos:** brave (brave-browser-rpm-release.s3), vivaldi (repo.vivaldi.com), claude-desktop (aaddrick.github.io community repo), zen-browser (Fedora COPR `sneexy/zen-browser`), starship + lazygit (`atim/starship`, `atim/lazygit` COPRs).

**System config files:**
- `/etc/brave/policies/managed/brave-policy.json` — full Brave hardening + Qwant default search. **Fetched at image build time from [ReinstallScripts](https://github.com/jakobhviid/ReinstallScripts/blob/main/Linux/assets/brave-policy.json)** — that's the canonical editable source. To change the policy: edit `Linux/assets/brave-policy.json` in ReinstallScripts → push → next image build picks it up automatically.
- `/etc/xdg/mimeapps.list` — Brave as system default browser (per-user override still wins)
- `/etc/pki/containers/bazzite-custom.pub` — cosign public key for client-side update verification
- `/usr/share/wireplumber/wireplumber.conf.d/rename-devices.conf` — friendly names for Sonos Ace + Sennheiser BTD 700 (no-op when those devices aren't connected). **Fetched at image build time from [ReinstallScripts](https://github.com/jakobhviid/ReinstallScripts/blob/main/Linux/assets/rename-devices.conf)** — same pattern as the brave policy.

**System services baked in:**
- `/usr/lib/systemd/system/bazzite-custom-flatpaks.service` — runs `flatpak preinstall -y --noninteractive` on boot, applies the file at `/usr/share/flatpak/preinstall.d/bazzite-custom.preinstall` (33 Flathub apps). Auto-enabled via `/usr/lib/systemd/system-preset/90-bazzite-custom.preset`.
- `/usr/lib/systemd/user/{brave,vivaldi,nextcloud}-unlock.service` — drops stale singleton-lock files at user login so the apps don't refuse to launch after crashes. Auto-enabled per-user via `/usr/lib/systemd/user-preset/90-bazzite-custom.preset`.

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
- **`proton-vpn-gnome-desktop`** — its `proton-vpn-daemon` ships a `%posttrans` scriptlet that calls `systemctl` to enable a service. In a build container there's no systemd PID 1, the scriptlet exits 1, and the whole `dnf5` transaction aborts. Stays in `RPM_PACKAGES` of `install-bazzite.sh` where it works on a live system.
- **`p7zip`** — replaced by `7zip` (modern Igor Pavlov port, in main F44).

**Stays in brew (intentional)**:
- `claude-code` — updates multiple times a week; brew gives same-day pickup vs the image's daily rebuild. Note: `claude-desktop` (the GUI) IS in the image; `claude-code` (the CLI) is the brew one.
- `dotnet` — niche language runtime; if you don't actively do .NET work this is dead weight.
- `typst`, `sesh`, `fzf-tab`, `zsh-autopair`, `zsh-completions`, `zsh-history-substring-search`, `zsh-you-should-use` — no Fedora/COPR packaging; would need `git clone` or `cargo install` patterns we deliberately avoid in the image.
- The 3 patched Nerd Font typefaces (FiraCode-NF, Hack-NF, MesloLG-NF) — only the `nerd-fonts` symbols-only equivalent is in F44; the patched typefaces would need GitHub-release tarballs.
- All other Flatpaks not in the [`bazzite-custom.preinstall`](system_files/usr/share/flatpak/preinstall.d/bazzite-custom.preinstall) list — handled per-machine via brew bundle.

---

## Architectural decisions and gotchas (lessons learned the hard way)

### 1. `/opt` is symlinked to `/var/opt` on Bazzite — must replace with a real directory

Atomic Fedora variants ship `/opt → /var/opt` so users can write to it on the live system. RPMs that install into `/opt` (Brave, Vivaldi, Claude Desktop) fail to unpack against that symlink with `cpio: mkdir failed - File exists` and the install aborts.

Fix in `Containerfile`: `RUN rm /opt && mkdir /opt` before any `dnf install`. This makes `/opt` part of the immutable image layer (like `/usr`). Apps in `/opt` now version with the OS — `bootc rollback` reverts them with the rest. Trade-off: you can't manually drop a tarball into `/opt` at runtime; use `/usr/local/` or `~/.local/` if you need to.

The image-template Containerfile literally has a commented hint about this: `# RUN rm /opt && mkdir /opt`. Uncomment it if your image installs anything into `/opt`.

**⚠ Layering caveat that follows from this**: `rpm-ostree install <pkg>` on top of this image will SILENTLY drop any `/opt` payload from the layered RPM. The new deployment commits with whatever the package put in `/usr/bin` (typically symlinks like `/usr/bin/1password → /opt/1Password/1password`), but the actual `/opt` files don't materialize because `/opt` is part of the read-only composefs root, not the per-deployment writable `/var/opt`. Symptom on the live system: dead symlink under `/usr/bin`, no app icon in GNOME, "command not found" when running. We rediscovered this trying to layer `1password` on top of this image; the symlink survived, the binary didn't. **Rule**: don't layer `/opt`-using RPMs on this image — install via brew (writes to `/home/linuxbrew`, which IS writable) or bake into the image at build time. Single-file `/usr/bin` packages (e.g. `1password-cli`'s `op`) layer fine.

### 2. Why `proton-vpn-gnome-desktop` is NOT in the image

Tempting to add (every machine wants Proton VPN), but it can't be image-baked: `proton-vpn-daemon` ships a `%posttrans` scriptlet that calls `systemctl daemon-reload` + `systemctl start`. In a build container `systemctl` returns *"System has not been booted with systemd as init system (PID 1). Can't operate."* → the scriptlet exits 1 → `dnf5` reports `Transaction failed: Rpm transaction failed.` and rolls back the **entire** transaction (every other package in the same `dnf5 install` line vanishes too — initial debugging is misleading because the failure is reported far from the offending package).

No flag avoids this; the scriptlet exits 1 unconditionally on systemctl failure. Workaround: install proton-vpn on the live system via `rpm-ostree install` — handled by `install-bazzite.sh` in the [ReinstallScripts](https://github.com/jakobhviid/ReinstallScripts) repo. Machines that never run that script (e.g. ones consuming the image only) won't have Proton VPN unless layered manually.

If you ever try to add proton-vpn to `build_files/build.sh`, the build will fail at the `dnf5 install` step with that exact transaction error — you've just rediscovered this gotcha.

### 3. Fedora-canonical GPG key location: `/etc/pki/rpm-gpg/RPM-GPG-KEY-<name>`

For any third-party repo, the canonical pattern is:

```bash
curl -fsSLo /etc/pki/rpm-gpg/RPM-GPG-KEY-foo https://example.com/key.asc
chmod 0644 /etc/pki/rpm-gpg/RPM-GPG-KEY-foo
cat > /etc/yum.repos.d/foo.repo <<EOF
[foo]
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-foo
EOF
```

NOT `gpgkey=https://...` — that "works" for `gpgcheck=1` (DNF auto-imports on first install) but is racy if `repo_gpgcheck=1` is also set. See gotcha #4 below.

### 4. dnf5 has a known race with `repo_gpgcheck=1` (`Signing key not found`)

Even with `gpgkey=file:///etc/pki/rpm-gpg/...` correctly set on disk, dnf5 in F44 can emit `repomd.xml GPG signature verification error: Signing key not found` for any repo that sets `repo_gpgcheck=1`. Bug regression in dnf5 5.2.11.x; fix landed in 5.2.12+ but Bazzite's F44 base hasn't pulled it yet. See [discussion](https://discussion.fedoraproject.org/t/why-does-dnf-give-gpg-signature-verification-errors-for-repos-with-repo-gpgcheck-1/147201).

Workaround: set `repo_gpgcheck=0` for affected repos. **Critically**: package-level `gpgcheck=1` continues to verify each RPM against the imported key, which is the security-critical check. `repo_gpgcheck=1` only adds metadata-fetch integrity, already covered by HTTPS+TLS to the upstream domains.

Affected in our build: Claude Desktop (community repo enables `repo_gpgcheck=1`). Once F44's dnf5 picks up 5.2.12+, flip the flag back to 1.

### 5. GitHub forks suppress the first push-triggered workflow run

Anti-abuse measure: a freshly forked repo's workflows do NOT auto-trigger on the first push to `main`, scheduled cron, or pull request. You have to manually trigger via `workflow_dispatch` once (`gh workflow run build.yml --ref main`). Subsequent pushes/schedules then fire normally.

### 6. Cosign with passphrase — non-default for the template

The upstream image-template README instructs `COSIGN_PASSWORD="" cosign generate-key-pair` and only ships a `SIGNING_SECRET` GHA secret. Passphrase-less keys are simpler but weaker if the GHA secret leaks alone (vs leaking with a separate passphrase secret).

Our setup uses a passphrase. The workflow's `Sign container image` step adds `COSIGN_PASSWORD: ${{ secrets.COSIGN_PASSWORD }}` to the env block alongside `COSIGN_PRIVATE_KEY: ${{ secrets.SIGNING_SECRET }}`. Both secrets must be set on the repo; both are required for signing to succeed.

### 7. Flatpak preinstall via Fedora's native mechanism (respects user uninstalls)

Drop a `[Flatpak Preinstall <appid>]` group per app into a `.preinstall` file under `/usr/share/flatpak/preinstall.d/`. A systemd oneshot service (ours: `bazzite-custom-flatpaks.service`) runs `flatpak preinstall -y --noninteractive` on boot, after `bazzite-flatpak-manager.service` has set up Flathub.

Critical property (per `man flatpak-preinstall`): *"Users can opt out of preinstalled flatpaks by simply uninstalling them, at which point they won't get automatically reinstalled again."* Flatpak itself tracks per-app what it preinstalled, so a `flatpak uninstall` is permanent — it survives image rebuilds.

A homegrown "list file + hash marker" approach (which I tried first) does NOT have this property: any list change triggers a full reinstall pass that re-deploys removed apps. Always use the canonical mechanism.

### 8. systemd presets vs explicit enable at build time

`/usr/lib/systemd/{system,user}-preset/<priority>-<name>.preset` files declare default-enable for shipped units. **For user units**, presets are evaluated automatically on user login — no build-time work needed. **For system units**, presets are NOT auto-applied during a container build, so you also need an explicit `systemctl enable <name>.service` in `build.sh` to lock the enable in. Without that, the unit ships but never starts.

### 9. bootc lint — handling upstream packaging quirks via sysusers.d/tmpfiles.d

Bazzite's bootc lint pass surfaces three classes of warning that typically come from upstream RPMs not following bootc-friendly conventions:

- **`nonempty-run-tmp`** (fixed): dnf leaves a state directory at `/run/dnf` after install. `/run` is a runtime tmpfs on the live system; lint flags any content there at build time. Fix: `rm -rf /run/dnf` at the end of `build.sh`.
- **`var-tmpfiles`** (fixed): dnf leaves cache directories at `/var/lib/dnf/repos/*` after install; Vivaldi auto-downloads `libffmpeg.so` to `/var/opt/vivaldi/media-codecs-*/`. `/var` is runtime state on bootc, so content there should be declared via `tmpfiles.d` or removed. Fixes:
   - `build_files/build.sh` `rm -rf /var/lib/dnf/repos` after `dnf5 clean all` (cache isn't needed at runtime — system is bootc-managed, not dnf-installed).
   - `build_files/build.sh` relocates Vivaldi's `libffmpeg.so` from `/var/opt/vivaldi/media-codecs-*/` to `/opt/vivaldi/lib/libffmpeg.so` (one of Vivaldi's documented search paths) and `rm -rf`'s `/var/opt/vivaldi`. **This is more than a lint fix** — it's a real bootc semantics improvement: keeping the codec in `/var` would mean Vivaldi binary updates in `/opt` would NOT update the codec library (since `/var` is preserved across upgrades), causing version skew. Now the codec is in the immutable image layer and updates atomically with the binary.
   - `system_files/usr/lib/tmpfiles.d/bazzite-custom.conf` declares the remaining `/var/lib/dnf` parent dir.

After all three: `Warnings: 0`, `Checks skipped: 1` (a kernel-mode-only check that doesn't apply).

---

## Verification + GHCR notes

### Verifying a signature manually

```bash
cosign verify --key cosign.pub ghcr.io/jakobhviid/bazzite-custom:latest
cosign verify --key cosign.pub ghcr.io/jakobhviid/bazzite-nvidia-custom:latest
```

### GHCR package visibility

GHCR packages default to private. To make them publicly pullable (so machines can rebase without authenticating to GHCR), flip both via:

```bash
gh api -X PATCH /user/packages/container/bazzite-custom -f visibility=public
gh api -X PATCH /user/packages/container/bazzite-nvidia-custom -f visibility=public
```

…or via the GitHub web UI under each package's settings.

---

## Build pipeline

`.github/workflows/build.yml`:

- **Matrix**: `bazzite-gnome` + `bazzite-gnome-nvidia-open` → `bazzite-custom` + `bazzite-nvidia-custom`. Both legs run in parallel.
- **Triggers**: push to `main` (excluding README), polling cron `30 */3 * * *` (every 3 hours), manual `workflow_dispatch`, plus `pull_request` (build-only, no push/sign).
- **Digest-gated polling**: the first step (`Check if base image changed`) compares the upstream Bazzite `:stable` digest to a `phd.hviid.bazzite-custom.base-digest` label stored on our last published image. On scheduled runs where the digests match, every subsequent step is skipped via `if:`. Effective behavior: the cron is a "poll for upstream change" check that exits in <30s when nothing has changed; the actual build only fires when Bazzite has published. Pushes and `workflow_dispatch` always build (you want to test your own changes immediately, regardless of upstream state).
- **Pickup latency**: at most 3 hours between Bazzite publishing a new `:stable` and our images being rebuilt from it.
- **Runtime when build actually fires**: ~5–7 min per leg with warm cache.
- **Concurrency**: per-variant cancel-in-progress (job-level, since matrix isn't visible at workflow-level concurrency).
- **GHA secrets required**: `SIGNING_SECRET` (cosign private key), `COSIGN_PASSWORD` (passphrase).
- **Cosign signs by digest**, not by tag — `cosign sign --key env://COSIGN_PRIVATE_KEY "${IMAGE}@${DIGEST}"` against the manifest digest from `steps.push.outputs.digest`. Binds the signature to the immutable manifest, silences the "uses a tag, not a digest" warning, and is one call instead of three (we previously looped over each tag).

---

## Cosign

- Algorithm: ECDSA P-256 (cosign default).
- Passphrase-encrypted private key.
- Public key committed at `cosign.pub` (repo root) and baked into the image at `/etc/pki/containers/bazzite-custom.pub`.
- Local key material stored in a password manager as a Document (cosign.key, cosign.key.decrypted, cosign.pub, passphrase).
- Decrypted key derivation: `scripts/decrypt-cosign-key.py` (reads the cosign envelope: scrypt-derived key + nacl secretbox over PKCS#8 DER, outputs standard PKCS#8 PEM). Run as `COSIGN_PASSWORD='<passphrase>' python3 scripts/decrypt-cosign-key.py cosign.key > cosign.key.decrypted`. Useful when you need the unencrypted key for archival — cosign itself ships no `export` subcommand.

---

## Updating the image

Most changes go in `build_files/build.sh` — add packages to the `dnf5 install -y` block, add new third-party repos by writing to `/etc/yum.repos.d/` and dropping keys in `/etc/pki/rpm-gpg/`.

Static system files go in `system_files/` — directory layout mirrors the rootfs (e.g., `system_files/etc/foo` lands at `/etc/foo`).

To add a flatpak: append a `[Flatpak Preinstall <appid>]` group to `system_files/usr/share/flatpak/preinstall.d/bazzite-custom.preinstall`. New apps install on next boot of a freshly-rebased machine; existing machines pick it up on the next rebuild + reboot.

To remove a flatpak from auto-install: delete its group from the `.preinstall` file. **This does NOT uninstall it from machines that already have it** — the removal is purely a "stop auto-installing on new deployments" signal. Existing installs persist until the user runs `flatpak uninstall <appid>`.

---

## Open follow-ups

- **GHCR package visibility**: confirm both packages are public (`gh api ...` or web UI), otherwise machines need to authenticate to pull.
- **dnf5 race**: monitor F44's dnf5 version; flip `repo_gpgcheck=1` back on for Claude Desktop once 5.2.12+ lands.
- **`install-bazzite.sh` cleanup**: with this image in production, the `RPM_PACKAGES` array can drop everything we now bake (keep only `proton-vpn-gnome-desktop`). Held back per project decision; deliberate when ready.
- **System SSH signing key for autonomous git commits**: a single-purpose Ed25519 SSH key at `~/.ssh/claude_signing_ed25519` is configured locally for this repo's commits. Public key not yet uploaded to GitHub as an SSH signing key (needs a `gh auth refresh -s admin:ssh_signing_key`), so commits show as "Unverified" until that's done. Cosmetic.
- **redhat-actions Node 24 upgrade**: `redhat-actions/buildah-build` and `redhat-actions/push-to-registry` are pinned to v2 (Node 20). GitHub forces Node 24 from June 2026, removes Node 20 in September 2026. When the maintainers ship v3 with Node 24, bump the pinned commit SHAs in `.github/workflows/build.yml`. Will also likely silence the "image is not a manifest list" fallback-chain noise from the push step.

---

## Upstream template notes

This repo was forked from [ublue-os/image-template](https://github.com/ublue-os/image-template). For questions about the upstream template — local building with `just`, `bootc-image-builder` for disk images, the `build-disk.yml` workflow for ISO generation, the artifacthub.io integration — see the [upstream README](https://github.com/ublue-os/image-template/blob/main/README.md). Most of what's there still applies, modulo the customizations documented above.

Useful upstream resources:
- [Universal Blue Forums](https://universal-blue.discourse.group/)
- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc discussion forums](https://github.com/bootc-dev/bootc/discussions)
