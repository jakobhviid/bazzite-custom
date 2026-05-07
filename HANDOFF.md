# Handoff — bazzite-custom initial setup

State of the repo as of the first work session. Working tree is **dirty and uncommitted** — review the diff against `main` (which is unmodified upstream `ublue-os/image-template`), then commit + push at your discretion.

## What's here

```
.github/workflows/build.yml          ← matrix build (bazzite-gnome + bazzite-gnome-nvidia-open),
                                       cosign signing with passphrase support
Containerfile                        ← parameterized with ARG BASE_IMAGE
build_files/build.sh                 ← all third-party repo setup + dnf5 install of:
                                       firefox, brave, vivaldi, zen, 1password +
                                       1password-cli, proton-vpn, claude-desktop,
                                       podman-compose, dash-to-panel + dash-to-dock,
                                       zsh, plus fedora-cisco-openh264 for Firefox h264
system_files/
  etc/brave/policies/managed/brave-policy.json   ← copied from ReinstallScripts/Linux/assets/
  etc/1password/custom_allowed_browsers          ← vivaldi-bin + zen-bin
  etc/xdg/mimeapps.list                          ← Brave as default browser system-wide
                                                   (per-user override still wins; mostly for Annika)
  etc/pki/containers/bazzite-custom.pub          ← cosign public key, baked in for client-side
                                                   verification of subsequent updates
cosign.pub                            ← same key, repo root (workflow doesn't read it but it's
                                       convention to commit the public half)
HANDOFF.md                            ← this file
```

The unmodified template files (`Justfile`, `disk_config/`, `artifacthub-repo.yml`, `.github/workflows/build-disk.yml`, `LICENSE`, `README.md`) are left in place. None of them block the build.

## Cosign keys

Generated fresh ECDSA P-256 keypair with a random 256-bit passphrase. Saved to:

```
/var/home/jakob/Developer/cosign-keys-DO-NOT-LOSE/
├── cosign.key       ← passphrase-encrypted private key (mode 600)
├── cosign.pub       ← public key (mode 644)
└── passphrase.txt   ← the passphrase, plain text (mode 600)
```

**Action needed: move all three to 1Password as a Document item, then delete the directory.**

GHA secrets already set on `jakobhviid/bazzite-custom`:
- `SIGNING_SECRET` ← contents of `cosign.key`
- `COSIGN_PASSWORD` ← contents of `passphrase.txt`

Both verified via `gh secret list`.

## Open decisions for when you're back

### 1. The fork's `main` branch is unmodified upstream — push strategy
Nothing is committed. Two reasonable paths:
- (a) Commit directly to `main` and push. First CI run kicks off immediately — both image variants build and sign, ~25 min.
- (b) Commit to a branch (`setup`?), open a PR to `main` for self-review. PRs run the workflow but skip the push/sign steps (the `if:` guards are `ref == main`).

I'd suggest (a) — you're the only reviewer, branching adds ceremony.

### 2. Annika's setup-from-zero path
Once the image publishes, rebasing Annika's machine looks like:

```bash
# First time only — accept image without verification
sudo rpm-ostree rebase ostree-unverified-image:registry:ghcr.io/jakobhviid/bazzite-nvidia-custom:latest
sudo systemctl reboot

# After reboot the policy file at /etc/pki/containers/bazzite-custom.pub is present.
# Add a policy.json entry so future updates verify against it:
sudo tee -a /etc/containers/policy.json  # see README in image-template for exact JSON
sudo rpm-ostree rebase ostree-image-signed:registry:ghcr.io/jakobhviid/bazzite-nvidia-custom:latest
```

Need to write a one-liner script for this. Could live in `ReinstallScripts/Linux/` as a `rebase.sh` that takes a machine name and figures out which variant. Or inline in HANDOFF.

### 3. What to drop from `ReinstallScripts/Linux/install-bazzite.sh` once the image is in use
Per your earlier instruction, **do not modify ReinstallScripts yet**. When ready, the cleanup is:
- Remove from `RPM_PACKAGES`: `podman-compose`, `brave-browser`, `1password`, `gnome-shell-extension-dash-to-panel`, `gnome-shell-extension-dash-to-dock`, `zsh`, `claude-desktop`, `zen-browser` (all baked into the image now)
- **Keep `proton-vpn-gnome-desktop`** in `RPM_PACKAGES` — its `proton-vpn-daemon` posttrans scriptlet calls `systemctl`, which kills the dnf5 transaction in a build container (no PID 1 systemd). Works fine via `rpm-ostree install` on a live system. Means Annika's machine has no Proton VPN unless she runs install-bazzite.sh, which she currently doesn't — flag if she needs it.
- Keep `gnome-extensions-cli` invocation for the 6 user-level extensions (`tilingshell`, `copyous`, `hide-minimized`, `quick-settings-audio-panel`, `quicksettings-audio-devices-renamer`, `CoverflowAltTab`) — these can't be RPMs
- Keep all `run_config_*` (per-user dconf, autostart, .desktop overrides, PWAs, brave policy *file deployment* can be removed since image bakes it, 1pw allowed_browsers same)
- The script becomes: brew bootstrap → brew bundle → gext → user dotfiles + dconf snapshots

### 4. Speaker EQ + unlock services
Currently per-user via `install-bazzite.sh`:
- `assets/speaker-eq.conf` — only useful on the X1 Carbon's thin laptop speakers; baking system-wide would activate on Atlas too. **Verdict: leave per-user (or move to system_files only on the laptop variant later).**
- `brave-unlock.service` + `nextcloud-unlock.service` — could move to `system_files/etc/systemd/user/` so every login enables them. Worth doing in v2; not blocking.

### 5. Currently layered on Atlas that isn't in the image
Your `rpm-ostree status` shows `file-roller-nautilus` and `seahorse-nautilus` layered manually. These aren't in `RPM_PACKAGES` either. Add to `build.sh` if you want them image-baked, or leave as drift.

### 6. NVIDIA driver — confirmed
RTX 5090 (Blackwell) → `bazzite-gnome-nvidia-open` is correct. Closed driver doesn't support Blackwell at all.

### 7. Build cadence
Workflow runs daily at **06:30 UTC** (30 min after Bazzite's own 06:00 UTC build to avoid racing against half-published upstream tags). Plus on every push to `main` (excluding README + HANDOFF changes). Plus manual via `workflow_dispatch`.

## Local sanity check before pushing
You can verify the Containerfile is syntactically clean with:

```bash
cd /var/home/jakob/Developer/bazzite-custom
podman build --build-arg BASE_IMAGE=bazzite-gnome -t bazzite-custom-test .
```

Takes 15–25 min. Will hit network (Brave, 1pw, Proton, Vivaldi, Zen Browser COPR repos). If it builds locally, CI will too.

## Things explicitly NOT done
- Did not modify anything under `/var/home/jakob/Developer/ReinstallScripts/` (per your instruction).
- Did not commit anything in `bazzite-custom` — left the working tree dirty for your review.
- Did not push anything to GitHub.
- Did not delete the cosign key working directory — that's your call after moving to 1Password.
