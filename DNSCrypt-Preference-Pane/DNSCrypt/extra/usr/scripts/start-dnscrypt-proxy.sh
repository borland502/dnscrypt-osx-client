#! /bin/sh

. ./common.inc

CERTIFICATE_MIN_VALIDITY=60

DNSCRYPT_LIB_BASE_DIR="${DNSCRYPT_USR_BASE_DIR}/lib"
export DYLD_LIBRARY_PATH="${DNSCRYPT_LIB_BASE_DIR}:${DYLD_LIBRARY_PATH}"

init_interfaces

mkdir -p -- "$DNSCRYPT_VAR_BASE_DIR" || exit 1

PROBES_BASE_DIR="${DNSCRYPT_VAR_BASE_DIR}/probes"
rm -fr "$PROBES_BASE_DIR" || exit 1
mkdir -p -- "$PROBES_BASE_DIR" || exit 1

RES_DIR="${PROBES_BASE_DIR}/results" || exit 1
mkdir -p -- "$RES_DIR" || exit 1

DESCRIPTIONS_DIR="${PROBES_BASE_DIR}/results-descriptions" || exit 1
mkdir -p -- "$DESCRIPTIONS_DIR" || exit 1

PID_DIR="${PROBES_BASE_DIR}/pids" || exit 1
mkdir -p -- "$PID_DIR" || exit 1

RESOLVER_NAME=$(./get-dnscrypt-resolver-name.sh) || exit 1

try_resolver() {
  local priority="$1"
  shift
  local description="$1"
  shift
  local args="$*"
  local pid_file="${PID_DIR}/${priority}.pid"

  logger_debug "Running a test dnscrypt proxy for [$description]"
  rm -f "${RES_DIR}/${priority}"
  alarmer 3 dnscrypt-proxy --pid="$pid_file" \
    --resolver-name="$RESOLVER_NAME" \
    --test="$CERTIFICATE_MIN_VALIDITY" $args
  if [ $? = 0 ]; then
    logger_debug "Certificate for [$description] received"
    echo "$args" > "${RES_DIR}/${priority}"
    echo "$description" > "${DESCRIPTIONS_DIR}/${priority}"
  fi
  rm -f "$pid_file"
}

get_plugin_args() {
  cat "$DNSCRYPT_PROXY_PLUGINS_BASE_FILE"[s-]*.enabled | { \
    local plugin_args=''
    local quoted_line

    while read line; do
      case "$line" in
        libdcplugin_*) plugin_args="${plugin_args} --plugin=${line}" ;;
      esac
    done
    logger_debug "Plugins to be used: [$plugin_args]"
    echo "$plugin_args"
  }
}

logger_debug "dnscrypt-proxy should be (re)started, stopping previous instance if needed"
./stop-dnscrypt-proxy.sh

wait_pids=""

try_resolver 1 "${RESOLVER_NAME} using DNSCrypt over UDP" \
  "--resolver-name=$RESOLVER_NAME" &
wait_pids="$wait_pids $!"

try_resolver 2 "${RESOLVER_NAME} using DNSCrypt over TCP" \
  "--resolver-name=$RESOLVER_NAME --tcp-only" &
wait_pids="$wait_pids $!"

for pid in $wait_pids; do
  wait
  best_file=$(ls "$RES_DIR" | head -n 1)
  [ x"$best_file" != "x" ] && break
  if [ ! -e "$DNSCRYPT_FILE" ]; then
    logger_debug "Aborted by user"
    exit 1
  fi
done

if [ x"$best_file" = "x" ]; then
  logger_debug "No usable proxy configuration has been found"
  exit 1
fi

./switch-cache-on.sh

plugins_args=''
if [ -r "${DNSCRYPT_PROXY_PLUGINS_BASE_FILE}s.enabled" ]; then
  plugin_args=$(get_plugin_args)
fi

best_args=$(cat "${RES_DIR}/${best_file}")

logger_debug "Starting dnscrypt-proxy $best_args"
eval dnscrypt-proxy $best_args --local-address="$INTERFACE_PROXY" \
  --resolver-name="$RESOLVER_NAME" --ephemeral-keys \
  --pidfile="$PROXY_PID_FILE" --user=daemon --daemonize $plugin_args

if [ $? != 0 ]; then
  [ -r "$PROXY_PID_FILE" ] && kill $(cat -- "$PROXY_PID_FILE")
  logger_debug "dnscrypt-proxy $best_args command failed, retrying"
  sleep 1
  killall dnscrypt-proxy
  sleep 1
  rm -f "$PROXY_PID_FILE"
  killall -9 dnscrypt-proxy
  sleep 1
  eval dnscrypt-proxy $best_args --local-address="$INTERFACE_PROXY" \
    --resolver-name="$RESOLVER_NAME" \
    --pidfile="$PROXY_PID_FILE" --user=daemon --daemonize $plugin_args || \
    exit 1
  logger_debug "dnscrypt-proxy $best_args worked after a retry"
fi

mv "${DESCRIPTIONS_DIR}/${best_file}" \
   "${STATES_DIR}/dnscrypt-proxy-description" 2>/dev/null || exit 0

[ -e "$RESOLVERS_LIST_STATE" ] && exit 0
touch "$RESOLVERS_LIST_STATE"
exec ./update-resolvers-list.sh
