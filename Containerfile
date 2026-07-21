FROM docker.io/steamcmd/steamcmd:debian-trixie AS builder

RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Download rcon-cli
RUN set -ex; \
    curl -sL https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz -o /tmp/rcon.tar.gz; \
    echo "6962a641ebf9a5957bd0cda1b8acf3e34a23686ae709f6c6a14ac3898521a5cc /tmp/rcon.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/rcon.tar.gz -C /tmp; \
    mv /tmp/rcon-0.10.3-amd64_linux/rcon /opt/rcon-cli; \
    chmod +x /opt/rcon-cli; \
    rm -rf /tmp/rcon.tar.gz /tmp/rcon-0.10.3-amd64_linux

# Download proton
ARG PROTON_VERSION=GE-Proton10-34
RUN set -ex; \
    mkdir -p "/opt/compatibilitytools.d"; \
    curl -o "/tmp/proton.tar.gz" -sL "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_VERSION}/${PROTON_VERSION}.tar.gz"; \
    tar -xzf "/tmp/proton.tar.gz" --strip-components 1 -C "/opt/compatibilitytools.d"; \
    rm -rf /tmp/proton.tar.gz

ARG ARK_BUILD_ID=unknown

# Download ark server files
RUN set -ex; \
    echo "Downloading ARK Ascended Server - Build ID: ${ARK_BUILD_ID}"; \
    mkdir -p /opt/ark; \
    steamcmd \
      +@sSteamCmdForcePlatformType windows \
      +force_install_dir /opt/ark \
      +login anonymous \
      +app_info_print 2430930 \
      +app_update 2430930 validate \
      +quit

FROM docker.io/library/debian:trixie-slim

ENV TZ=UTC
ENV PROTON_USE_ESYNC=1

# Proton requirements
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends python3 libfreetype6; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Setup machine-id to silence a proton warning
RUN set -ex; \
    tr -d '-' < /proc/sys/kernel/random/uuid > /etc/machine-id

RUN useradd -m -s /bin/bash steam

COPY --from=builder --chown=root:root /opt/rcon-cli /usr/local/bin/rcon-cli
COPY --from=builder --chown=steam:steam /opt/ark /home/steam/ark
COPY --from=builder --chown=steam:steam /opt/compatibilitytools.d /home/steam/Steam/compatibilitytools.d

USER steam
WORKDIR /home/steam/

# Setup compatibility data
RUN set -ex; \
    mkdir -p "Steam/steamapps/compatdata/2430930"; \
    mkdir -p "Steam/steamapps/common/ark/"; \
    cp -r Steam/compatibilitytools.d/files/share/default_pfx Steam/steamapps/compatdata/2430930

COPY --chown=steam:steam entrypoint.sh entrypoint.sh

CMD ["/home/steam/entrypoint.sh"]
