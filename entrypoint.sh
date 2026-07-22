#!/usr/bin/env bash
set -euo pipefail

function join_by {
  local delimiter=${1-}
  if shift 1; then
    printf %s "${@/#/$delimiter}"
  fi
}

rcon_port="${RCON_PORT:-27020}"
admin_password="${SERVER_ADMIN_PASSWORD:?missing environment variable}"

function server_args {
  local session_name="SessionName=\"${SESSION_NAME:?missing environment variable}\""

  # RCON cannot be disabled, as it's needed for graceful shutdown
  local rcon_args="RCONEnabled=True?RCONPort=${rcon_port}"

  local opt_server_args=()

  if [ -n "${SERVER_PASSWORD+x}" ]; then
    opt_server_args+=("ServerPassword=$SERVER_PASSWORD")
  fi

  if [ -n "${EXTRA_ARGS+x}" ]; then
    opt_server_args+=("${EXTRA_ARGS}")
  fi

  # Required to be the last argument
  opt_server_args+=("ServerAdminPassword=$admin_password")

  echo "${session_name}?${rcon_args}$(join_by "?" "${opt_server_args[@]}")"
}

function server_options {
  local server_port="-port=${SERVER_PORT:-7777}"

  local opt_server_options=()

  if [ "${DISABLE_BATTLEYE:-}" = "TRUE" ]; then
    opt_server_options+=("-NoBattlEye")
  fi

  if [ -n "${MAX_PLAYERS:-}" ]; then
    opt_server_options+=("-WinLiveMaxPlayers=${MAX_PLAYERS}")
  fi

  if [ -n "${MOD_IDS:-}" ]; then
    opt_server_options+=("-mods=${MOD_IDS}")
  fi

  if [ -n "${PASSIVE_MOD_IDS:-}" ]; then
    opt_server_options+=("-passivemods=${PASSIVE_MOD_IDS}")
  fi

  if [ -n "${CLUSTER_ID:-}" ]; then
    opt_server_options+=("-clusterid=${CLUSTER_ID}")
  fi

  if [ -n "${EXTRA_OPTIONS+x}" ]; then
    opt_server_options+=("${EXTRA_OPTIONS}")
  fi

  echo "${server_port} -servergamelog -servergamelogincludetribelogs -ServerRCONOutputTribeLogs$(join_by " " "${opt_server_options[@]}")"
}

install_path="/home/steam/ark"
exec_path="${install_path}/ShooterGame/Binaries/Win64/ArkAscendedServer.exe"
lock_file="${install_path}/ark.lock"

echo "🛠 Checking and fixing directory permissions..."
# Target the paths we know get auto-created by container engines for nested mounts
# This removes sticky bits (chmod -t) and ensures the owner has write access (chmod u+w)
for dir in \
  "${install_path}/ShooterGame/Saved" \
  "${install_path}/ShooterGame/Saved/Config/WindowsServer" \
  "${install_path}/ShooterGame/Saved/clusters"
do
  if [ -d "$dir" ]; then
    chmod -t "$dir" 2>/dev/null || true
    chmod u+rwx "$dir" 2>/dev/null || true
  fi
done

# Fail fast if we still don't have write access
if [ ! -w "${install_path}/ShooterGame/Saved" ]; then
  echo "❌ ERROR: Cannot write to ${install_path}/ShooterGame/Saved. Check host permissions!" >&2
  exit 1
fi

if [[ ! -e "$exec_path" || "${DISABLE_UPDATE_CHECK_AT_STARTUP:-}" != "TRUE" ]]; then
  echo "🔍 Preparing for update..."

  # Open file descriptor 9 for writing to the lock file
  exec 9> $lock_file

  # Attempt to acquire the installation lock, wait up to 15 minutes
  if ! flock -w 900 9; then
    echo "❌ Failed to acquire lock after 15 minutes. Exiting." >&2
    exit 1
  fi

  echo "⏳ Proceeding with installation..."
  /home/steam/steamcmd/steamcmd.sh +@sSteamCmdForcePlatformType windows +force_install_dir ${install_path} +login anonymous +app_update 2430930 validate +quit
  echo "✅ Installation/update completed"

  # Release the lock
  exec 9>&-
else
  echo "ℹ️ Server installation detected and update check disabled, skipping install"
fi

map="${SERVER_MAP:-TheIsland_WP}"
server_params="$map?Listen?$(server_args) $(server_options)"

export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/steam/Steam/"
export STEAM_COMPAT_DATA_PATH="/home/steam/Steam/steamapps/compatdata/2430930"

start_cmd=("/home/steam/Steam/compatibilitytools.d/proton" "run" "$exec_path" $server_params)

echo "🚀 Starting ARK Survival Ascended server..."
echo "🛠 ${start_cmd[*]}"

# Start the game with setsid so bash does not own the process and won't kill it upon SIGTERM
setsid "${start_cmd[@]}" &
server_pid=$!

log_file="${install_path}/ShooterGame/Saved/Logs/ShooterGame.log"
mkdir -p "$(dirname "$log_file")"

# Truncate file. We could possibly make a backup. Ark also create backup logs, I don't understand what triggers it.
: > "$log_file"

# Forward the game logs to the main process output
tail -n +1 -F "$log_file" &
tail_pid=$!

_shutdown() {
    echo "🛑 Stop signal received. Sending RCON shutdown command..."

    # Broadcast imminent shutdown to players
    rcon-cli -a "localhost:${rcon_port}" -p "${admin_password}" "Broadcast Server will shutdown..."

    # The 'DoExit' command forces a save and shutdown
    rcon-cli -a "localhost:${rcon_port}" -p "${admin_password}" "DoExit"

    # Wait for the server process to finish
    wait $server_pid

    kill $tail_pid

    echo "✅ Server exited cleanly."
    exit 0
}

trap _shutdown SIGTERM SIGINT

# Keep the script alive while waiting for the server
wait $server_pid
