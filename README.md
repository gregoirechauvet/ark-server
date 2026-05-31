# Ark Survival Ascended

Container image of the Ark Survival Ascended dedicated server.

## Available variables

| Name                              | Default        | Description                                                                                                                                                           |  
|-----------------------------------|----------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `SESSION_NAME`                    |                | Required. Server name as visible in game. Can contain spaces                                                                                                          |
| `SERVER_MAP`                      | `TheIsland_WP` | Instance map                                                                                                                                                          |
| `SERVER_PASSWORD`                 |                | If set, password that is required to connect                                                                                                                          |
| `SERVER_ADMIN_PASSWORD`           |                | Admin password                                                                                                                                                        |
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

## Compose example

```yaml
services:
  ark-server:
    image: ghcr.io/gregoirechauvet/ark-server:proton-10
    restart: unless-stopped
    init: true
    mem_limit: 16G
    userns_mode: keep-id # For podman runtime - remove for docker runtime
    stop_grace_period: 1m
    environment:
      - SESSION_NAME=Gotta tame 'em all!
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

## File permissions

⚠️ A common quirk when mounting files is host-container permission conflicts.  
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
