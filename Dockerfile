# syntax=docker/dockerfile:1.20
ARG UBUNTU_VERSION=24.04

FROM ubuntu:${UBUNTU_VERSION} AS steamcmd-base
# Fail RUN pipelines (e.g. `wget ... | debconf-set-selections`) on any
# non-zero exit, not just the last command's - inherited by every later
# stage since they all FROM this one.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Los_Angeles LANG=en_US.UTF-8 LANGUAGE=en_US:en

# Install basic dependencies
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    apt-get update \
    && apt-get install -y --no-install-recommends \
    ca-certificates tzdata software-properties-common \
    curl wget unzip sudo gnupg2 gosu dos2unix locales

# Set timezone and locale
RUN ln -sf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && locale-gen en_US.UTF-8

# Install SteamCMD
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    dpkg --add-architecture i386 \
    && echo steam steam/question select "I AGREE" | debconf-set-selections \
    && echo steam steam/license note "" | debconf-set-selections \
    && apt-get update && apt-get install -y steamcmd

# Symlink SteamCMD
RUN ln -s /usr/games/steamcmd /usr/bin/steamcmd && steamcmd +quit

# Set up Steam directories and libraries for root (used by the `steamcmd
# +quit` sanity check above, and any RUN steps a downstream Dockerfile adds
# while still root). These almost always land empty at build time - nothing
# has been steamcmd-installed into linux32/64 yet - which is exactly why this
# can't be the only place this happens: see dockerify's
# setup_steam_client_symlinks(), which does the same thing for whichever user
# actually runs the server, retried right before it's spawned.
RUN mkdir -p /root/.steam \
    && ln -s /root/.local/share/Steam/steamcmd/linux32 /root/.steam/sdk32 \
    && ln -s /root/.local/share/Steam/steamcmd/linux64 /root/.steam/sdk64 \
    && ln -s /root/.steam/sdk32/steamclient.so /root/.steam/sdk32/steamservice.so || true \
    && ln -s /root/.steam/sdk64/steamclient.so /root/.steam/sdk64/steamservice.so || true

# Covers both root (build-time RUN steps) and the `steam` user (the runtime
# user in every final image) - a symlink only created under /root/.steam is
# useless to the steam user's process, and a missing entry here is silently
# ignored by the dynamic linker, so listing both unconditionally is safe.
ENV LD_LIBRARY_PATH="/root/.steam/sdk32:/root/.steam/sdk64:/home/steam/.steam/sdk32:/home/steam/.steam/sdk64:$LD_LIBRARY_PATH"

# Ensure no existing user/group with UID/GID 1000
RUN if getent passwd 1000; then userdel -r "$(getent passwd 1000 | cut -d: -f1)"; fi \
    && if getent group 1000; then groupdel "$(getent group 1000 | cut -d: -f1)"; fi

# Create 'steam' user and group with UID and GID 1000
RUN groupadd -g 1000 steam \
    && useradd -m -u 1000 -g steam -s /bin/bash steam \
    && usermod -aG sudo steam \
    && echo 'steam ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set permissions for 'steam' user
RUN chown -R steam:steam /home/steam

# Create script directories
RUN mkdir -p /opt/steamcmd-bases/scripts.d /opt/steamcmd-bases/bin /opt/steamcmd-bases/lib

# Copy scripts to base image
COPY --chmod=755 scripts/entrypoint.sh /opt/steamcmd-bases/entrypoint.sh
COPY --chmod=755 scripts/lib/deps.sh /opt/steamcmd-bases/lib/
COPY --chmod=755 scripts/scripts.d/00-common-init.sh /opt/steamcmd-bases/scripts.d/

# Set entrypoint
ENTRYPOINT ["/opt/steamcmd-bases/entrypoint.sh"]

#################
# Wine Extension
#################
FROM steamcmd-base AS wine-base
ARG WINEARCH=win64
ENV WINEDEBUG=fixme-all

# Pre-accept EULA for Microsoft core fonts
RUN echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections

# Install Wine repository and Wine following official instructions
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates gnupg2 software-properties-common && \
    dpkg --add-architecture i386 && \
    mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    chmod 644 /etc/apt/keyrings/winehq-archive.key && \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable winbind cabextract

# Optional: Install Winetricks
ADD --chmod=755 https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks /usr/local/bin/winetricks

# Copy Wine-specific scripts
COPY --chmod=755 scripts/scripts.d/10-wine-init.sh /opt/steamcmd-bases/scripts.d/

# Copy pre-built binaries: test-exe (compatibility test executable) and
# dockerify (installs/runs Wine & Proton - see crates/dockerify)
COPY --chmod=755 target/release/test-exe /opt/steamcmd-bases/bin/test-exe.exe
COPY --chmod=755 target/release/dockerify /opt/steamcmd-bases/bin/dockerify

# Create symlinks for utility scripts
RUN ln -sf /opt/steamcmd-bases/bin/dockerify /usr/local/bin/dockerify

#################
# Proton Extension
#################
FROM wine-base AS proton-base
# "latest" resolves to whatever GloriousEggroll's newest GitHub release is at
# build time; pin an exact tag (e.g. GE-Proton9-20) for reproducible builds
ARG PROTON_VERSION=latest
ENV STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/steam/.steam/steam \
    STEAM_COMPAT_DATA_PATH=/home/steam/.proton \
    WINETRICKS_LATEST_VERSION_CHECK=disabled

# Install additional packages required for Proton.
# libvulkan1 + mesa-vulkan-drivers give DXVK a software Vulkan device
# (llvmpipe/lavapipe) to initialize against - without it, any game that
# creates a Vulkan instance fails immediately since there's no GPU in the
# container (not every dedicated server needs this - many run fully headless
# with no renderer at all - but it's there for the ones that do). Xvfb + a
# display are also required before Proton is invoked at all (see
# 20-proton-init.sh), or it fails the same way even earlier. libfreetype6:i386
# is needed alongside the 64-bit build since Proton's bundled Wine still runs
# 32-bit components.
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    apt-get update \
    && apt-get install -y --no-install-recommends \
    xvfb python3 python3-pip libfreetype6 libfreetype6-dev libfreetype6:i386 \
    libxkbcommon0 xauth jq curl dbus \
    libvulkan1 mesa-vulkan-drivers

# A stable, valid /etc/machine-id (rather than none/ephemeral) avoids dbus
# warnings from Wine/Proton components that expect one to be present.
RUN rm -f /etc/machine-id && dbus-uuidgen --ensure=/etc/machine-id

# Build-time smoke test: fail the build immediately if the Vulkan loader and
# a software device (lavapipe) aren't wired up correctly, rather than only
# discovering it later when a game actually tries to render.
RUN /opt/steamcmd-bases/bin/test-exe.exe --check-vulkan

USER steam
WORKDIR /home/steam

# Create Steam directory structure following official patterns
RUN mkdir -p /home/steam/.steam/root/compatibilitytools.d \
    && mkdir -p /home/steam/.proton

# Download and install GE-Proton: either the pinned PROTON_VERSION tag, or
# whatever is currently latest on GitHub. Also points the "current" symlink
# at it (see dockerify's install_proton) - this is what makes PROTON_PATH
# stable below and what proton-manager.sh use/install repoints later.
RUN dockerify install proton --version "${PROTON_VERSION}"

# Create necessary symlinks for Steam structure
RUN mkdir -p /home/steam/.steam/steam \
    && ln -sf /home/steam/.steam/root /home/steam/.steam/steam \
    && mkdir -p /home/steam/.steam/root/steamapps/common

USER root

# Copy Proton-specific initialization scripts
COPY --chmod=755 scripts/scripts.d/20-proton-init.sh /opt/steamcmd-bases/scripts.d/
COPY --chmod=755 scripts/scripts.d/99-cleanup.sh /opt/steamcmd-bases/scripts.d/

# Add symbolic links for libraries. (steam's own ~/.steam/sdk32|64 ->
# steamclient.so is deliberately NOT set up here: at this point in the build
# nothing has run steamcmd as the `steam` user yet, so there's nothing real
# to link to, and a symlink created here would be under the wrong user
# anyway once a downstream image's `RUN steamcmd ...` actually populates it.
# dockerify's setup_steam_client_symlinks() - run automatically by
# `dockerify run` right before launching, and available manually as
# `dockerify link-steam-client` - does this correctly as the `steam` user
# once steamcmd has actually installed something.)
RUN ln -s /usr/lib/i386-linux-gnu/libncurses.so.6 /usr/lib/i386-linux-gnu/libncurses.so.5 2>/dev/null || true \
    && ln -s /usr/lib/x86_64-linux-gnu/libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5 2>/dev/null || true \
    && chown -R steam:steam /home/steam

# The "current" symlink (created by dockerify install proton above) keeps
# PROTON_PATH stable regardless of what PROTON_VERSION/"latest" resolved to,
# and is what `dockerify proton use` repoints at runtime.
RUN echo "export PROTON_PATH=/home/steam/.steam/root/compatibilitytools.d/current/proton" >> /home/steam/.bashrc

USER steam
WORKDIR /home/steam

# Verify installation
RUN echo "Installed Proton version:" && ls -la /home/steam/.steam/root/compatibilitytools.d/

#################
# Final Targets
#################
FROM steamcmd-base AS base
WORKDIR /home/steam
USER steam
CMD ["steamcmd", "+quit"]

FROM wine-base AS wine
WORKDIR /home/steam
USER steam
CMD ["steamcmd", "+@sSteamCmdForcePlatformType", "windows", "+quit"]

FROM proton-base AS proton
WORKDIR /home/steam
USER steam
# Stable regardless of which GE-Proton version PROTON_VERSION resolved to at
# build time (see the "current" symlink created in proton-base above)
ENV PROTON_PATH=/home/steam/.steam/steam/compatibilitytools.d/current/proton
CMD ["steamcmd", "+quit"]
