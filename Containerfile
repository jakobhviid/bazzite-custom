ARG BASE_IMAGE=bazzite-gnome
ARG BASE_TAG=stable

# Build context: scripts in build_files/ are mounted at /ctx during the install RUN
# but never copied into the final image.
FROM scratch AS ctx
COPY build_files /

# Base image — chosen by matrix at build time.
# Variants we publish:
#   bazzite-gnome             → bazzite-custom        (Intel-only, X1 Carbon)
#   bazzite-gnome-nvidia-open → bazzite-nvidia-custom (NVIDIA open driver, Atlas + Annika)
FROM ghcr.io/ublue-os/${BASE_IMAGE}:${BASE_TAG}

# Bazzite (and other atomic Fedora variants) ship /opt as a symlink to /var/opt
# so users can write to it on the live system. RPMs that install into /opt
# (Brave, Vivaldi, Claude Desktop) fail to unpack against that
# symlink — "cpio: mkdir failed - File exists". Replace the symlink with a real
# directory so /opt is part of the immutable image layer.
RUN rm /opt && mkdir /opt

# System-level files baked into / verbatim. Goes in BEFORE build.sh so dnf5 sees
# any pre-staged repo configs and policy files at install time.
COPY system_files/ /

# Run all package install + repo setup in one layer with caches mounted.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# Validate the image is bootc-correct (catches missing /usr split, broken
# symlinks, etc). Cheap, run last.
RUN bootc container lint
