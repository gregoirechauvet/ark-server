#!/usr/bin/env bash
set -euo pipefail

function join_by {
  local delimiter=${1-}
  if shift 1; then
    printf %s "${@/#/$delimiter}"
  fi
}

function server_args {
  local session_name="SessionName=\"${SESSION_NAME:?missing environment variable}\""

  # RCON cannot be disabled, as it's needed for graceful shutdown
  local rcon_args="RCONEnabled=True?RCONPort=${RCON_PORT:-27020}"

  local opt_server_args=()

  if [ -n "${SERVER_PASSWORD+x}" ]; then
    opt_server_args+=("ServerPassword=$SERVER_PASSWORD")
  fi

  if [ -n "${SERVER_ADMIN_PASSWORD+x}" ]; then
    opt_server_args+=("ServerAdminPassword=$SERVER_ADMIN_PASSWORD")
  fi

  if [ -n "${EXTRA_ARGS+x}" ]; then
    opt_server_args+=("${EXTRA_ARGS}")
  fi

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

#if [ ! -e "/home/steam/CONTAINER_ALREADY_STARTED_PLACEHOLDER" ]; then
#    echo "***Downloading ARK Ascended Server"
#    /home/steam/steamcmd/steamcmd.sh +force_install_dir "/home/steam/ark" +login anonymous +app_update 2430930 +quit
#	if [ "$updateonstart" = false ]; then
#	touch "/home/steam/CONTAINER_ALREADY_STARTED_PLACEHOLDER"
#    fi
#fi

map="${SERVER_MAP:-TheIsland_WP}"
server_params="$map?Listen?$(server_args) $(server_options)"

export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/steam/Steam/"
export STEAM_COMPAT_DATA_PATH="/home/steam/Steam/steamapps/compatdata/2430930"

start_cmd=("/home/steam/Steam/compatibilitytools.d/proton" "run" "/home/steam/ark/ShooterGame/Binaries/Win64/ArkAscendedServer.exe" "$server_params")

echo "Starting ARK Survival Ascended server..."
echo "+ ${start_cmd[*]}"

"${start_cmd[@]}" >&1 2>&1 &
server_pid=$!
# server_pgid=$(awk '{print $5}' /proc/$server_pid/stat)

# Forward the game logs to the main process output
tail -n +1 -F "/home/steam/ark/ShooterGame/Saved/Logs/ShooterGame.log" >&1 2>&1 &
tail_pid=$!

## Define the shutdown function
_graceful_shutdown() {
    echo "Stop signal received. Sending RCON shutdown commands..."

    # The 'doexit' command forces a save and shutdown
    rcon-cli -a "localhost:${RCON_PORT:-27020}" -p "${SERVER_PASSWORD}" -c "doexit"

    # Wait for the server process to finish
    wait $server_pid

    kill $tail_pid

    echo "Server exited cleanly."
    exit 0
}

#_force_shutdown() {
#  echo "Will attempt force shutdown..."
#
#  kill -KILL -"$server_pgid" 2>/dev/null
#  echo "Exited"
#  exit 0
#}

trap _graceful_shutdown SIGTERM
#trap _force_shutdown SIGINT

## Keep the script alive while waiting for the server
wait $server_pid