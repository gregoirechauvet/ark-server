# Ark Survival Ascended

Container image for Ark Survival Ascended dedicated server.

## Features

* **Graceful shutdown:** Intercepts container stop signals to automatically trigger a `DoExit` command via RCON, ensuring the world state is saved before the container exits.
* **Unprivileged execution:** Runs strictly as a non-root user (`UID 1000:1000`). It avoids host-level permission overwrites and is fully compatible with rootless Podman.
* **Cluster-friendly:** Implements a SteamCMD lock, allowing multiple server instances to safely share a single installation folder without conflicting during updates.

## Available variables

| Name                              | Default        | Description                                                                                                                                                           |  
|-----------------------------------|----------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `SESSION_NAME`                    |                | Required. Server name as visible in game. Can contain spaces                                                                                                          |
| `SERVER_MAP`                      | `TheIsland_WP` | Instance map                                                                                                                                                          |
| `SERVER_PASSWORD`                 |                | If set, password that is required to connect                                                                                                                          |
| `SERVER_ADMIN_PASSWORD`           |                | Required. Admin password                                                                                                                                              |
| `SERVER_PORT`                     | `7777`         | Game port<br/>Note that peer port will always be `SERVER_PORT + 1`                                                                                                    |
| `EXTRA_ARGS`                      |                | Extra arguments to pass to the startup command. Multiple values can be provided, separated by question marks, e.g. `ServerCrosshair=true?ShowMapPlayerLocation=false` |
| `RCON_PORT`                       | `27020`        | RCON port                                                                                                                                                             |
| `MAX_PLAYERS`                     |                | Max players                                                                                                                                                           |
| `MOD_IDS`                         |                | Comma-separated list of mod IDs, e.g. `1234,5678`                                                                                                                     |
| `PASSIVE_MOD_IDS`                 |                | Comma-separated list of passive mod IDs, e.g. `1234,5678`                                                                                                             |
| `CLUSTER_ID`                      |                | Cluster ID for server transfer                                                                                                                                        |
| `EXTRA_OPTIONS`                   |                | Extra options to pass to the startup command. Multiple values can be provided, separated by spaces, e.g. `-NoWildBabies -ForceAllowCaveFlyers`                        |
| `DISABLE_BATTLEYE`                |                | Set to `TRUE` to disable BattlEye                                                                                                                                     |
| `DISABLE_UPDATE_CHECK_AT_STARTUP` |                | Set to `TRUE` to prevent checking for updates when the server starts                                                                                                  |

## Volume Mounts (Persistent Storage)

To ensure your server data persists across container recreations, you must map specific paths inside the container to persistent storage. You can use either **host directories (bind mounts)** or **named volumes**.

*   **Bind Mounts (`./data:/...`):** Recommended. Makes it infinitely easier to manually edit `.ini` configuration files, install mods, or manage backups directly from your host machine. (See the *File Permissions* section below to avoid crash issues).
*   **Named Volumes (`ark_data:/...`):** Docker manages the storage. Harder to access the files directly, but completely eliminates host-to-container permission issues.

| Container Path | Description |
|---|---|
| `/home/steam/ark` | **The core installation directory.** Mounting this avoids re-downloading the entire ~15+ GB game server every time the container starts. For a single-server setup, mounting this single path is usually enough, as it includes the `Saved` folder. |
| `/home/steam/ark/ShooterGame/Saved` | **The instance data directory.** This contains map save files, player profiles, and your `.ini` config files (located in `Config/WindowsServer/`). In a cluster setup, you must mount this separately for each server to prevent them from overwriting each other's configuration and map saves. |
| `/home/steam/ark/ShooterGame/Saved/clusters` | **The cluster transfer directory.** If you are running multiple maps in a cluster, all containers must share this single mount so players can upload and download characters/dinos between servers. |


## Networking & Port Forwarding

If you are hosting this server on a home network or behind a NAT/Firewall, you must explicitly open and forward the following ports to your host machine's local IP address so external players can connect.

*   **Game Port:** `7777 UDP` (Matches the `SERVER_PORT` variable)
*   **Peer Port:** `7778 UDP` (Always `SERVER_PORT + 1`)
*   **RCON Port:** `27020 TCP` (*Optional.* Matches the `RCON_PORT` variable. Only required if you intend to use external admin tools to manage your server remotely. Can safely be remapped to another port in the host)

## Graceful shutdown

The ARK server periodically saves the game state to disk (every 15 minutes by default).  
If the server is forcefully stopped, unsaved progress is lost and the server will roll back to the last persisted checkpoint.

To prevent this, the container implements a graceful shutdown. Upon receiving a `SIGTERM`, it sends a `DoExit` command via RCON, triggering a world save and clean exit. 

> [!NOTE]  
> You must increase the container's stop grace period (`--stop-timeout` in CLI / `stop_grace_period` in Compose). By default, container runtimes wait only 10 seconds before sending a `SIGKILL`, which will terminate the process before the save completes. 

In practice, the server usually takes less than a minute to stop. Setting the grace period to 2 minutes (`120s` or `2m`) is recommended. Alternatively, you would have to manually send a `SaveWorld` command via RCON or the in-game admin console before stopping the container.

## File permissions

A common quirk when mounting files is host-container permission conflicts.  
This container runs strictly as an unprivileged user with UID/GID `1000:1000`. It will not attempt to rewrite host file permissions.

### For rootless podman runtime

Add `userns_mode: keep-id` to your service definition in the compose file (or pass `--userns=keep-id` if using the CLI). This tells Podman to natively map the container's internal user to your host user, bypassing permission issues.

### For docker runtime

Because Docker does not use `keep-id` mapping, you must strictly provision the host directories before starting the container. If you let Docker auto-create the mount paths, it will create them as `root`, causing the server to crash.

Ensure the target directories exist and are explicitly owned by UID `1000`:
```bash
mkdir -p ./data
sudo chown -R 1000:1000 ./data
```

## Compose examples

### Single instance

```yaml
services:
  ark-server:
    image: ghcr.io/gregoirechauvet/ark-server:proton-10
    restart: unless-stopped
    init: true # Starts init process within the container to properly forward signals and gracefully shutdown the server
    mem_limit: 16G
    userns_mode: keep-id # For podman runtime - remove for docker runtime
    stop_grace_period: 1m # Increase grace period to allow the server to stop
    environment:
      - SESSION_NAME=Gotta tame 'em all!
      - SERVER_MAP=TheIsland_WP
      - MAX_PLAYERS=20
      - DISABLE_BATTLEYE=TRUE
      - SERVER_PORT=7777
      - SERVER_PASSWORD=pikachu
      - SERVER_ADMIN_PASSWORD=pikapika
    ports:
      - "7777:7777/udp"
      - "7778:7778/udp"
      # Optionally bind the RCON port for remote administration
      # - "27020:27020/tcp"
    volumes:
      - ./data:/home/steam/ark
```

### Cluster setup

In a cluster setup, you can share the installation folder to avoid each instance downloading its own copy of the server files. The image ensures that only one instance attempts to install or update the server via SteamCMD concurrently.

However, you must configure nested mounts for the save locations to isolate instance-specific data while sharing the cluster directory.

```yaml
services:
  theisland:
    image: ghcr.io/gregoirechauvet/ark-server:proton-10
    restart: unless-stopped
    init: true
    mem_limit: 16G
    userns_mode: keep-id
    stop_grace_period: 1m
    environment:
      - SESSION_NAME=MyCluster - The Island
      - SERVER_MAP=TheIsland_WP
      - MAX_PLAYERS=20
      - SERVER_PORT=7777
      - SERVER_PASSWORD=pikachu
      - SERVER_ADMIN_PASSWORD=pikapika
      - CLUSTER_ID=MyCluster
    ports:
      - "7777:7777/udp"
      - "7778:7778/udp"
    volumes:
      - ./data:/home/steam/ark # Shared installation folder between instances - only one instance will attempt installation at a time
      - ./cluster:/home/steam/ark/ShooterGame/Saved/clusters # Shared mount for server transfer
      - ./theisland:/home/steam/ark/ShooterGame/Saved # Instance-specific save location

  scorchedearth:
    image: ghcr.io/gregoirechauvet/ark-server:proton-10
    restart: unless-stopped
    init: true
    mem_limit: 16G
    userns_mode: keep-id
    stop_grace_period: 1m
    environment:
      - SESSION_NAME=MyCluster - Scorched Earth
      - SERVER_MAP=ScorchedEarth_WP
      - MAX_PLAYERS=20
      - SERVER_PORT=7779 # Important to change the internal port and not just remap it so the server can advertise itself properly
      - SERVER_PASSWORD=pikachu
      - SERVER_ADMIN_PASSWORD=pikapika
      - CLUSTER_ID=MyCluster
    ports:
      - "7779:7779/udp"
      - "7780:7780/udp"
    volumes:
      - ./data:/home/steam/ark # Shared installation folder between instances - only one instance will attempt installation at a time
      - ./cluster:/home/steam/ark/ShooterGame/Saved/clusters # Shared mount for server transfer
      - ./scorchedearth:/home/steam/ark/ShooterGame/Saved # Instance-specific save location
```

### Dynamic config

See the [Ark Wiki on DynamicConfig](https://ark.wiki.gg/wiki/Server_configuration#DynamicConfig) for detailed mechanics.

Create a `dynamicconfig.ini` file locally:
```
TamingSpeedMultiplier=2.0
HarvestAmountMultiplier=2.0
XPMultiplier=2.0
```

Use a lightweight web server (like NGINX) to serve the file to the game server container(s):

```yaml
services:
  ark-config:
    image: nginx:alpine
    container_name: ark-config
    volumes:
      - ./dynamicconfig.ini:/usr/share/nginx/html/dynamicconfig.ini:ro

  theisland:
    image: ghcr.io/gregoirechauvet/ark-server:proton-10
    restart: unless-stopped
    init: true
    mem_limit: 16G
    userns_mode: keep-id
    stop_grace_period: 1m
    environment:
      - SESSION_NAME=Gotta tame 'em all
      - SERVER_MAP=TheIsland_WP
      - MAX_PLAYERS=20
      - SERVER_PORT=7777
      - SERVER_PASSWORD=pikachu
      - SERVER_ADMIN_PASSWORD=pikapika
      - EXTRA_OPTIONS=-UseDynamicConfig
      - EXTRA_ARGS=CustomDynamicConfigUrl=http://ark-config:80/dynamicconfig.ini
    ports:
      - "7777:7777/udp"
      - "7778:7778/udp"
    volumes:
      - ./data:/home/steam/ark
```

## Alternatives

Depending on your requirements, you might prefer a different approach to hosting Ark Survival Ascended. Here are some other notable container setups:
- https://github.com/Acekorneya/Ark-Survival-Ascended-Server
- https://github.com/Johnny-Knighten/ark-sa-server
