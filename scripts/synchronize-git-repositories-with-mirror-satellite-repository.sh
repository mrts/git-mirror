#!/bin/bash

# Synchronize two Git repositories from an intermediate satellite mirror.
#
# See ../README.md for details.

TRIGGERED_BY=${1:-origin}

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_FULL_PATH="$SCRIPT_DIR/$(basename "$0" '.sh')"

CONFIGFILE="$SCRIPT_DIR/synchronize-git-mirror.config"
LIBFILE="$SCRIPT_DIR/synchronize-git-mirror.shlib"

LOGFILE="${SCRIPT_FULL_PATH}.log"
LOCKDIR="${SCRIPT_FULL_PATH}.lock"

function include_file()
{
	local THEFILE="$1"

	if [[ ! -r "$THEFILE" ]]
	then
	       echo "$THEFILE does not exist or is unreadable" >&2
	       exit 1
	fi

	source "$THEFILE"
}

include_file "$CONFIGFILE"
include_file "$LIBFILE"

wait_for_lock "$LOCKDIR"

rotate_logs "$LOGFILE"

function synchronize_from_to()
{
	local from=$1
	local to=$2

	echo "Synchronizing $from -> $to" >> "$LOGFILE"

	git --git-dir "$CONF_GITDIR" remote update --prune $from >> "$LOGFILE" 2>&1
	check_status "git --git-dir $CONF_GITDIR remote update --prune $from" "$LOGFILE"

	git --git-dir "$CONF_GITDIR" push --mirror --prune $to >> "$LOGFILE" 2>&1
	check_status "git --git-dir $CONF_GITDIR push --mirror --prune $to" "$LOGFILE"

	echo "Success" >> "$LOGFILE"
}

echo "..............................." >> "$LOGFILE"
echo "Triggered by $TRIGGERED_BY" >> "$LOGFILE"

if [[ "$TRIGGERED_BY" == "origin" ]]
then
	synchronize_from_to origin "$CONF_OTHER_REPO"
else
	synchronize_from_to "$CONF_OTHER_REPO" origin
fi
