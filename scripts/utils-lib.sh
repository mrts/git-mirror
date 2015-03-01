#!/bin/bash

# TODO:
#
# function handle_error()
# {
#	if mail has not yet been sent
#		create guard for $1
#		echo "$1 failed, see $LOGFILE"
#	else if mail has been sent once for this error (i.e. guard exists)
#		update count for $1 guard to 2 or add marker
#		echo remainder and say that no more notices
# 		will be echoed until the guard has been removed
#	else don't echo anything
#
#	exit 1
# }

set -u

function warn()
{
	local MESSAGE="$1"

	echo "$MESSAGE" >> "$LOGFILE"
	echo "$MESSAGE" >&2
}

function error_exit()
{
	local THECMD="$1"
	local LOGFILE="$2"

	echo "$THECMD FAILED" >> "$LOGFILE"
	echo "$THECMD failed, see $LOGFILE" >&2
	exit 1
}

function check_status()
{
	LAST_STATUS=$?

	local THECMD="$1"
	local LOGFILE="$2"

	echo "=>" >> "$LOGFILE"
	[[ $LAST_STATUS = 0 ]] || error_exit "$THECMD" "$LOGFILE"
	[[ $LAST_STATUS = 0 ]] && echo "$THECMD successful" >> "$LOGFILE"
	echo "----------------------------------------------" >> "$LOGFILE"
}

function rotate_logs()
{
	local LOGFILE="$1"

	if [[ -e "$LOGFILE" ]]; then
		for i in 3 2 1; do
			FROM="${LOGFILE}.${i}"
			TO="${LOGFILE}.$((i + 1))"
			[[ -e "$FROM" ]] && cp "$FROM" "$TO"
		done
		cp "$LOGFILE" "${LOGFILE}.1"
	fi

	> "$LOGFILE"
}

function release_lock()
{
	local LOCKDIR="$1"

	for toplevel_dir in /*; do
		if [[ "$LOCKDIR" = "$toplevel_dir" ]]; then
			echo "Refusing to rm -rf $LOCKDIR" >&2
			exit 1
		fi
	done

	rm -rf "$LOCKDIR"
}

function acquire_lock()
{
	# Inspired by http://wiki.bash-hackers.org/howto/mutex
	# and http://wiki.grzegorz.wierzowiecki.pl/code:mutex-in-bash

	local LOCKDIR="$1"
	local PIDFILE="${LOCKDIR}/pid"

	if mkdir "$LOCKDIR" &>/dev/null; then
		# lock succeeded

		# remove $LOCKDIR on exit
		trap "release_lock \"$LOCKDIR\"" EXIT \
			|| { echo 'trap exit failed' >&2; exit 1; }

		# will trigger the EXIT trap above by `exit`
		trap 'echo "Sync script killed" >&2; exit 1' HUP INT QUIT TERM \
			|| { echo 'trap killsignals failed' >&2; exit 1; }

		echo "$$" >"$PIDFILE"

		return 0

	else
		# lock failed, now check if the other PID is alive
		OTHERPID="$(cat "$PIDFILE" 2>/dev/null)"

		if [[ $? != 0 ]]; then
			# PID file does not exist - probably direcotry
			# is being deleted
			return 1
		fi

		if ! kill -0 $OTHERPID &>/dev/null; then
			# lock is stale, remove it and restart
			echo "Stale lock in sync script" >&2
			release_lock "$LOCKDIR"
			acquire_lock "$LOCKDIR"
			return $?

		else
			# lock is valid and OTHERPID is active - exit,
			# we're locked!
			return 1
		fi
	fi
}

function wait_for_lock()
{
	local LOCKDIR="$1"

	# For timeout:
	#  - local WAIT_TIMEOUT=120
	#  - add `&& [[ $i -lt $WAIT_TIMEOUT ]]` to while condition
	#  - add ((i++)) into while body

	while ! acquire_lock "$LOCKDIR"; do
		warn "Waiting for lock '$LOCKDIR'"
		sleep 1
	done
}
