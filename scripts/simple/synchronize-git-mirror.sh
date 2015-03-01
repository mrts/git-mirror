#!/bin/bash

# Synchronize two-way Git mirror with a remote repository.
#
# See ../README.md for details.

TRIGGERED_BY=${1:-fetch}

set -u

SCRIPT_FULL_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0" '.sh')"

CONFIGFILE="${SCRIPT_FULL_PATH}.config"

LIBFILE="${SCRIPT_FULL_PATH}.shlib"

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

function push_changes()
{
	echo "Pushing changes to $CONF_ORIGIN_URL" >> "$LOGFILE"
	git --git-dir "$CONF_GITDIR" push --mirror --prune >> "$LOGFILE" 2>&1
	check_status "git --git-dir $CONF_GITDIR push --mirror --prune" "$LOGFILE"
}

function fetch_changes()
{
	echo "Fetching changes from $CONF_ORIGIN_URL" >> "$LOGFILE"
	git --git-dir "$CONF_GITDIR" remote update --prune >> "$LOGFILE" 2>&1
	check_status "git --git-dir $CONF_GITDIR remote update --prune" "$LOGFILE"
}

echo "..............................." >> "$LOGFILE"
echo "Triggered by $TRIGGERED_BY" >> "$LOGFILE"

if [[ "$TRIGGERED_BY" != "fetch" ]]
then
	push_changes
	fetch_changes
else
	fetch_changes
	push_changes
fi
