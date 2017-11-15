#! /bin/sh

. ./common.inc

[ -r "$DNSCRYPT_RESOLVER_NAME_FILE" ] && \
  sed 's/[^a-zA-Z0-9.-]/_/g' < "$DNSCRYPT_RESOLVER_NAME_FILE" && exit 0

exec ./get-random-resolver.sh
