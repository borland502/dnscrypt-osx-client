#! /bin/sh

. ./common.inc

exec find "$TICKETS_DIR" -type f -name 'ticket-*' | wc -l | sed 's/ *//g'

