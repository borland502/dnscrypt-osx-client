#! /bin/sh

. ./common.inc

tickets_count=$(./get-tickets-count.sh)
[ "$tickets_count" != '0' ] && exit 0

if [ x"$1" != 'x--boot' ]; then
  ./check-network-change.sh || exit 0
fi

logger_debug "Network configuration changed"

lockfile -1 -r 30 "$HANDLERS_LOCK_FILE" || exit 1
./set-dns-to-dhcp.sh
if [ ! -e "$DNSCRYPT_FILE" ]; then
  rm -f "$HANDLERS_LOCK_FILE"
  exit 0
fi

rm -f "${STATES_DIR}/controls.cksum"

./switch-to-dnscrypt-if-required.sh
rm -f "$HANDLERS_LOCK_FILE"
