# bazzite-custom

A small ublue/Bazzite derivative for Jakob's three-machine GNOME fleet. Forked from [ublue-os/image-template](https://github.com/ublue-os/image-template); the original template README is preserved at the bottom of this file under [Upstream template notes](#upstream-template-notes).

Two image variants built in parallel from one Containerfile via a GHA matrix:

| Image | Base | Target machines |
|---|---|---|
| `ghcr.io/jakobhviid/bazzite-custom:latest` | `ghcr.io/ublue-os/bazzite-gnome:stable` | X1 Carbon Gen 13 (Intel only) |
| `ghcr.io/jakobhviid/bazzite-nvidia-custom:latest` | `ghcr.io/ublue-os/bazzite-gnome-nvidia-open:stable` | Atlas (RTX 5090), Annika's desktop |

Both signed with cosign. The build runs on every push to `main` and polls upstream Bazzite every 3 hours — it only rebuilds when the upstream `:stable` digest has actually changed (see [Build pipeline](#build-pipeline) below for the digest-gated polling mechanism).

## Rebase a machine

Pick the line for your hardware. First-time rebase uses `ostree-unverified-image:` because the cosign trust rule isn't on the machine yet — it ships *inside* the new image at `/etc/pki/containers/bazzite-custom.pub`. After the first reboot you can switch to `ostree-image-signed:` and updates verify automatically.

**Intel-only laptop (X1 Carbon):**
```bash
sudo rpm-ostree rebase ostree-unverified-image:registry:ghcr.io/jakobhviid/bazzite-custom:latest
sudo systemctl reboot
```

**NVIDIA desktop (Atlas, Annika):**
```bash
sudo rpm-ostree rebase ostree-unverified-image:registry:ghcr.io/jakobhviid/bazzite-nvidia-custom:latest
sudo systemctl reboot
```

After reboot — promote to signed (one-time, optional but recommended):
```bash
# X1 Carbon
sudo rpm-ostree rebase ostree-image-signed:registry:ghcr.io/jakobhviid/bazzite-custom:latest
# NVIDIA desktops
sudo rpm-ostree rebase ostree-image-signed:registry:ghcr.io/jakobhviid/bazzite-nvidia-custom:latest
```

Subsequent updates: `sudo bootc upgrade` (or `sudo rpm-ostree upgrade`) — pulls the daily-rebuilt image, verifies the cosign signature, stages, applies on next reboot.

---

## What's baked in

**RPMs from Fedora F44 main:** firefox, firefox-langpacks, brave-browser, vivaldi-stable, 1password, 1password-cli, claude-desktop, zen-browser, podman-compose, gnome-shell-extension-{dash-to-panel,dash-to-dock}, zsh, bat, btop, butane, eza, fzf, htop, jq, just, tmux, zoxide, zsh-autosuggestions, zsh-syntax-highlighting, libheif-tools, unrar, 7zip, gnome-tweaks, nerd-fonts.

**RPMs from custom repos:** brave (brave-browser-rpm-release.s3), 1password (1password.com), vivaldi (repo.vivaldi.com), claude-desktop (aaddrick.github.io community repo), zen-browser (Fedora COPR `sneexy/zen-browser`), starship + lazygit (`atim/starship`, `atim/lazygit` COPRs).

**System config files:**
- `/etc/brave/policies/managed/brave-policy.json` — full Brave hardening + Qwant default search
- `/etc/1password/custom_allowed_browsers` — vivaldi-bin + zen-bin (so 1Password browser extension talks to non-Chrome/Firefox browsers)
- `/etc/xdg/mimeapps.list` — Brave as system default browser (per-user override still wins)
- `/etc/pki/containers/bazzite-custom.pub` — cosign public key for client-side update verification
- `/usr/share/wireplumber/wireplumber.conf.d/rename-devices.conf` — friendly names for Sonos Ace + Sennheiser BTD 700 (no-op when those devices aren't connected)

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

Atomic Fedora variants ship `/opt → /var/opt` so users can write to it on the live system. RPMs that install into `/opt` (Brave, Vivaldi, 1Password, Claude Desktop) fail to unpack against that symlink with `cpio: mkdir failed - File exists` and the install aborts.

Fix in `Containerfile`: `RUN rm /opt && mkdir /opt` before any `dnf install`. This makes `/opt` part of the immutable image layer (like `/usr`). Apps in `/opt` now version with the OS — `bootc rollback` reverts them with the rest. Trade-off: you can't manually drop a tarball into `/opt` at runtime; use `/usr/local/` or `~/.local/` if you need to.

The image-template Containerfile literally has a commented hint about this: `# RUN rm /opt && mkdir /opt`. Uncomment it if your image installs anything into `/opt`.

### 2. Why `proton-vpn-gnome-desktop` is NOT in the image

Tempting to add (every machine wants Proton VPN), but it can't be image-baked: `proton-vpn-daemon` ships a `%posttrans` scriptlet that calls `systemctl daemon-reload` + `systemctl start`. In a build container `systemctl` returns *"System has not been booted with systemd as init system (PID 1). Can't operate."* → the scriptlet exits 1 → `dnf5` reports `Transaction failed: Rpm transaction failed.` and rolls back the **entire** transaction (every other package in the same `dnf5 install` line vanishes too — initial debugging is misleading because the failure is reported far from the offending package).

No flag avoids this; the scriptlet exits 1 unconditionally on systemctl failure. Workaround: install proton-vpn on the live system via `rpm-ostree install` — `install-bazzite.sh`'s `RPM_PACKAGES` array keeps it for that path. Annika's machine, which doesn't run `install-bazzite.sh`, has no Proton VPN unless she layers it manually.

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

Affected in our build: 1Password (upstream template enables `repo_gpgcheck=1`), Claude Desktop (community repo enables it). Once F44's dnf5 picks up 5.2.12+, flip the flag back to 1.

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
- **`sysusers`** (fixed): 1Password's RPM creates `onepassword` + `onepassword-cli` groups in `/etc/group` but ships no `sysusers.d` declaration. On bootc deploys that recreate `/etc`, the groups would be lost without one. Fix: `system_files/usr/lib/sysusers.d/bazzite-custom.conf` declares both with `-` (auto-GID).
- **`var-tmpfiles`** (mostly fixed): Vivaldi installs codec data under `/var/opt/vivaldi/`, dnf leaves cache directories at `/var/lib/dnf/repos/*` after install. `/var` is runtime state on bootc, so anything that must exist there needs declaring. Fix: `system_files/usr/lib/tmpfiles.d/bazzite-custom.conf` declares the dnf parent dir + Vivaldi's parent/target/symlink trio. `build_files/build.sh` also `rm -rf /var/lib/dnf/repos` (the cache subdirs aren't needed at runtime — bootc, not dnf-managed). **Two brittle bits**: the Vivaldi symlink hardcodes `7.9` and a dated git suffix `git-2026-02-09`. If Vivaldi bumps version and the symlink shape changes, lint will flag a new warning and the tmpfiles entry needs updating to match. **One residual warning that can't be silenced**: `/var/opt/vivaldi/media-codecs-git-…/libffmpeg.so` is a binary file in /var. tmpfiles.d declares existence + permissions but cannot store file content, so we can't fully cover it. The file persists across bootc upgrades and Vivaldi works — purely cosmetic lint noise from upstream packaging.

After all three: `Warnings: 1` (the unavoidable libffmpeg.so file noted above), `Checks skipped: 1` (a kernel-mode-only check that doesn't apply).

---

## Using the image

### Initial rebase (one-time per machine)

GHCR packages default to private. After the first build succeeds, mark them public via `gh api -X PATCH /user/packages/container/bazzite-custom -f visibility=public` (and same for `bazzite-nvidia-custom`), or via the GitHub web UI.

Then on each machine:

```bash
# X1 Carbon (Intel only)
sudo rpm-ostree rebase ostree-image-signed:registry:ghcr.io/jakobhviid/bazzite-custom:latest

# Atlas + Annika's machine (NVIDIA open)
sudo rpm-ostree rebase ostree-image-signed:registry:ghcr.io/jakobhviid/bazzite-nvidia-custom:latest

sudo systemctl reboot
```

**First rebase note**: if your `/etc/containers/policy.json` doesn't yet have a trust rule pointing at `bazzite-custom.pub`, the signed rebase will fail. Either rebase via `ostree-unverified-image:` once first (the new image will then ship the pub key at `/etc/pki/containers/bazzite-custom.pub` so you can add the policy rule and re-rebase signed), or pre-add the policy rule before the first rebase.

### Ongoing updates

Automatic via `bootc upgrade` / `rpm-ostree upgrade` — pulls the daily-rebuilt image, verifies signature, stages, applies on next reboot.

### Verifying a signature manually

```bash
cosign verify --key cosign.pub ghcr.io/jakobhviid/bazzite-custom:latest
cosign verify --key cosign.pub ghcr.io/jakobhviid/bazzite-nvidia-custom:latest
```

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
- Local key material stored in 1Password as a Document (cosign.key, cosign.key.decrypted, cosign.pub, passphrase).
- Decrypted key derivation: `scripts/decrypt-cosign-key.py` (reads the cosign envelope: scrypt-derived key + nacl secretbox over PKCS#8 DER, outputs standard PKCS#8 PEM). Run as `COSIGN_PASSWORD='<passphrase>' python3 scripts/decrypt-cosign-key.py cosign.key > cosign.key.decrypted`. Useful when you need the unencrypted key for archival in 1Password — cosign itself ships no `export` subcommand.

---

## Updating the image

Most changes go in `build_files/build.sh` — add packages to the `dnf5 install -y` block, add new third-party repos by writing to `/etc/yum.repos.d/` and dropping keys in `/etc/pki/rpm-gpg/`.

Static system files go in `system_files/` — directory layout mirrors the rootfs (e.g., `system_files/etc/foo` lands at `/etc/foo`).

To add a flatpak: append a `[Flatpak Preinstall <appid>]` group to `system_files/usr/share/flatpak/preinstall.d/bazzite-custom.preinstall`. New apps install on next boot of a freshly-rebased machine; existing machines pick it up on the next rebuild + reboot.

To remove a flatpak from auto-install: delete its group from the `.preinstall` file. **This does NOT uninstall it from machines that already have it** — the removal is purely a "stop auto-installing on new deployments" signal. Existing installs persist until the user runs `flatpak uninstall <appid>`.

---

## Open follow-ups

- **GHCR package visibility**: confirm both packages are public (`gh api ...` or web UI), otherwise machines need to authenticate to pull.
- **dnf5 race**: monitor F44's dnf5 version; flip `repo_gpgcheck=1` back on for 1Password + Claude Desktop once 5.2.12+ lands.
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
