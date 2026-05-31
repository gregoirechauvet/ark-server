FROM cm2network/steamcmd:root-trixie

ENV TZ=UTC
ENV PROTON_USE_ESYNC=1

# Proton requirements
RUN set -ex; \
    apt-get update; \
    apt-get install -y --no-install-recommends python3 libfreetype6; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Setup rcon-cli
RUN set -ex; \
    curl -sL https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz -o /tmp/rcon.tar.gz; \
    echo "6962a641ebf9a5957bd0cda1b8acf3e34a23686ae709f6c6a14ac3898521a5cc  /tmp/rcon.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/rcon.tar.gz -C /tmp; \
    mv /tmp/rcon-0.10.3-amd64_linux/rcon /usr/local/bin/rcon-cli; \
    chmod +x /usr/local/bin/rcon-cli; \
    rm -rf /tmp/rcon.tar.gz /tmp/rcon-0.10.3-amd64_linux

# Setup machine-id to silence a proton warning
RUN set -ex; \
    cat /proc/sys/kernel/random/uuid | tr -d '-' > /etc/machine-id

# Switch to steam user before installating proton
USER steam
WORKDIR /home/steam/

# Download proton
ARG PROTON_VERSION=GE-Proton10-34
RUN set -ex; \
    mkdir -p "Steam/compatibilitytools.d"; \
    curl -o "/tmp/proton.tar.gz" -sL "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_VERSION}/${PROTON_VERSION}.tar.gz"; \
    tar -xzf "/tmp/proton.tar.gz" --strip-components 1 -C "Steam/compatibilitytools.d"; \
    rm -rf /tmp/proton.tar.gz

# Setup compatibility data
RUN set -ex; \
    mkdir -p "Steam/steamapps/compatdata/2430930"; \
    mkdir -p "Steam/steamapps/common/ark/"; \
    cp -r Steam/compatibilitytools.d/files/share/default_pfx Steam/steamapps/compatdata/2430930

COPY --chown=steam:steam entrypoint.sh entrypoint.sh

CMD ["/home/steam/entrypoint.sh"]
