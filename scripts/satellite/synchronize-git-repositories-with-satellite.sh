#!/bin/bash

# Synchronize two Git repositories from an intermediate satellite mirror.
#
# See ../README.md for details.

TRIGGERED_BY=${1:-origin}
REFS=${2:-all}

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_FULL_PATH="$SCRIPT_DIR/$(basename "$0" '.sh')"

CONFIGFILE="${SCRIPT_FULL_PATH}.config"
LIBFILE="$SCRIPT_DIR/../utils-lib.sh"

LOGFILE="${SCRIPT_FULL_PATH}.log"
LOCKDIR_BASE="${SCRIPT_FULL_PATH}.lock"

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

[[ "$TRIGGERED_BY" == "origin" ]] || [[ "$TRIGGERED_BY" == "$CONF_OTHER_REMOTE" ]] || {

	warn "$0: expected first argument to be either 'origin' or '$CONF_OTHER_REMOTE', but got '$1'"
	exit 1
}

ORIGIN_LOCK="${LOCKDIR_BASE}.origin"
OTHER_REMOTE_LOCK="${LOCKDIR_BASE}.${CONF_OTHER_REMOTE}"

if [[ "$TRIGGERED_BY" == "origin" ]]
then
	# synchronization triggered from other remote's post-receive hook
	# still in progress, exit
	[[ -d "$OTHER_REMOTE_LOCK" ]] && exit 0

	wait_for_lock "$ORIGIN_LOCK"
else
	wait_for_lock "$OTHER_REMOTE_LOCK"
fi

rotate_logs "$LOGFILE"

function synchronize_from_to()
{
	local from=$1
	local to=$2
	local refs=$3

	echo "Synchronizing $refs from $from to $to" >> "$LOGFILE"

	if [[ "$refs" == "all" ]]
	then
		refs='--mirror'
	fi

	git --git-dir "$CONF_GITDIR" remote update --prune $from >> "$LOGFILE" 2>&1
	check_status "git --git-dir $CONF_GITDIR remote update --prune $from" "$LOGFILE"

	git --git-dir "$CONF_GITDIR" push --prune $to $refs >> "$LOGFILE" 2>&1
	check_status "git --git-dir $CONF_GITDIR push --prune $to $refs" "$LOGFILE"

	echo "Success" >> "$LOGFILE"
}

echo "..............................." >> "$LOGFILE"
echo "Triggered by $TRIGGERED_BY" >> "$LOGFILE"

if [[ "$TRIGGERED_BY" == "origin" ]]
then
	synchronize_from_to origin "$CONF_OTHER_REMOTE" "$REFS"
else
	synchronize_from_to "$CONF_OTHER_REMOTE" origin "$REFS"
fi
