# syntax=docker/dockerfile:1.15
ARG UBUNTU_VERSION=24.04

FROM ubuntu:${UBUNTU_VERSION} AS steamcmd-base
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
    && apt-get update && apt-get install -y steamcmd \
    && apt-get clean

# Symlink SteamCMD
RUN ln -s /usr/games/steamcmd /usr/bin/steamcmd && steamcmd +quit

# Set up Steam directories and libraries
RUN mkdir -p /root/.steam \
    && ln -s /root/.local/share/Steam/steamcmd/linux32 /root/.steam/sdk32 \
    && ln -s /root/.local/share/Steam/steamcmd/linux64 /root/.steam/sdk64 \
    && ln -s /root/.steam/sdk32/steamclient.so /root/.steam/sdk32/steamservice.so || true \
    && ln -s /root/.steam/sdk64/steamclient.so /root/.steam/sdk64/steamservice.so || true

ENV LD_LIBRARY_PATH="/root/.steam/sdk32:/root/.steam/sdk64:$LD_LIBRARY_PATH"

# Ensure no existing user/group with UID/GID 1000
RUN if getent passwd 1000; then userdel -r $(getent passwd 1000 | cut -d: -f1); fi \
    && if getent group 1000; then groupdel $(getent group 1000 | cut -d: -f1); fi

# Create 'steam' user and group with UID and GID 1000
RUN groupadd -g 1000 steam \
    && useradd -m -u 1000 -g steam -s /bin/bash steam \
    && usermod -aG sudo steam \
    && echo 'steam ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set permissions for 'steam' user
RUN chown -R steam:steam /home/steam

# Create script directories
RUN mkdir -p /opt/steamcmd-bases/scripts.d /opt/steamcmd-bases/bin

# Copy scripts to base image
COPY --chmod=755 scripts/entrypoint.sh /opt/steamcmd-bases/entrypoint.sh
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
    apt-get update && apt-get install -y ca-certificates gnupg2 software-properties-common && \
    dpkg --add-architecture i386 && \
    mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    chmod 644 /etc/apt/keyrings/winehq-archive.key && \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable winbind cabextract && \
    apt-get clean

# Optional: Install Winetricks
ADD --chmod=755 https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks /usr/local/bin/winetricks

# Copy Wine-specific scripts
COPY --chmod=755 scripts/scripts.d/10-wine-init.sh /opt/steamcmd-bases/scripts.d/
COPY --chmod=755 scripts/bin/game-launcher.sh /opt/steamcmd-bases/bin/

# Create symlinks for utility scripts
RUN ln -sf /opt/steamcmd-bases/bin/game-launcher.sh /usr/local/bin/game-launcher

#################
# Proton Extension
#################
FROM wine-base AS proton-base
ARG PROTON_VERSION=8.0-6
ENV STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/steam/.steam/steam \
    STEAM_COMPAT_DATA_PATH=/home/steam/.proton \
    WINETRICKS_LATEST_VERSION_CHECK=disabled

# Install additional packages required for Proton
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    apt-get update \
    && apt-get install -y --no-install-recommends \
       xvfb python3 python3-pip libfreetype6 libfreetype6-dev \
       libxkbcommon0 xauth jq curl \
    && apt-get clean

USER steam
WORKDIR /home/steam

# Create Steam directory structure following official patterns
RUN mkdir -p /home/steam/.steam/root/compatibilitytools.d \
    && mkdir -p /home/steam/.proton

# Download and install latest GE-Proton version automatically
RUN mkdir -p /tmp/proton-ge \
    && cd /tmp/proton-ge \
    && LATEST_VERSION=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | jq -r .tag_name) \
    && echo "Installing GloriousEggroll Proton version: ${LATEST_VERSION}" \
    && DOWNLOAD_URL=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .browser_download_url') \
    && curl -sL "${DOWNLOAD_URL}" -o proton.tar.gz \
    && tar xzf proton.tar.gz -C /home/steam/.steam/root/compatibilitytools.d/ \
    && rm -rf /tmp/proton-ge

# Create necessary symlinks for Steam structure
RUN mkdir -p /home/steam/.steam/steam \
    && ln -sf /home/steam/.steam/root /home/steam/.steam/steam \
    && mkdir -p /home/steam/.steam/root/steamapps/common

USER root

# Copy utility scripts
COPY --chmod=755 scripts/proton-run.sh /usr/local/bin/proton-run
COPY --chmod=755 scripts/proton-manager.sh /usr/local/bin/proton-manager
COPY --chmod=755 scripts/proton-diagnose.sh /usr/local/bin/proton-diagnose

# Copy Proton-specific initialization scripts
COPY --chmod=755 scripts/scripts.d/20-proton-init.sh /opt/steamcmd-bases/scripts.d/
COPY --chmod=755 scripts/scripts.d/99-cleanup.sh /opt/steamcmd-bases/scripts.d/

# Add symbolic links for libraries
RUN ln -s /usr/lib/i386-linux-gnu/libncurses.so.6 /usr/lib/i386-linux-gnu/libncurses.so.5 2>/dev/null || true \
    && ln -s /usr/lib/x86_64-linux-gnu/libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5 2>/dev/null || true \
    && mkdir -p /home/steam/.steam/sdk64 \
    && ln -sf /root/.steam/sdk64/steamclient.so /home/steam/.steam/sdk64/steamclient.so 2>/dev/null || true \
    && chown -R steam:steam /home/steam

# Set environment variable for the exact Proton path
RUN PROTON_DIR=$(find /home/steam/.steam/root/compatibilitytools.d -maxdepth 1 -type d -name "GE-Proton*" | sort -V | tail -n 1) \
    && echo "export PROTON_PATH=${PROTON_DIR}/proton" >> /home/steam/.bashrc

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
# Set default Proton binary path
ENV PROTON_PATH=/home/steam/.steam/steam/compatibilitytools.d/GE-Proton${PROTON_VERSION}/proton
CMD ["steamcmd", "+quit"]
