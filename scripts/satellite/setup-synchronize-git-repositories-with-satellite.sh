#!/bin/bash

# Setup two-way Git mirror with a remote repository.
#
# See ../README.md for details.
#
# Assure passwordless access works, no password propmts should appear below.

set -u
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SCRIPT_NAME='synchronize-git-repositories-with-satellite'
SYNCHRONIZE_SCRIPT="$SCRIPT_DIR/${SCRIPT_NAME}.sh"
CONFIGFILE="$SCRIPT_DIR/${SCRIPT_NAME}.config"

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

POSTRECEIVE_HOOK="$CONF_OTHER_GITDIR/custom_hooks/post-receive"

function setup_satellite_repository()
{
	echo "Setting up satellite repository"

	git clone --mirror $CONF_ORIGIN_URL $CONF_GITDIR

	pushd $CONF_GITDIR

	git config --unset remote.origin.mirror # can't push refs with mirror

	git remote add --mirror $CONF_OTHER_REMOTE $CONF_OTHER_URL
	git config --unset remote.${CONF_OTHER_REMOTE}.mirror

	popd

	echo "Testing synchronization from origin to $CONF_OTHER_REMOTE"
	"$SYNCHRONIZE_SCRIPT"

	echo "Testing synchronization from $CONF_OTHER_REMOTE to origin"
	"$SYNCHRONIZE_SCRIPT" $CONF_OTHER_REMOTE

	echo "Setting up satellite repository: SUCCESS"
}

function setup_postreceive_hook_to_push_changes_from_other_to_origin()
{
	echo '---'
	echo "Setting up $CONF_OTHER_REMOTE post-receive hook $POSTRECEIVE_HOOK"

	mkdir `dirname "$POSTRECEIVE_HOOK"`

	cp -a "$SCRIPT_DIR/git-post-receive-hook-for-updating-satellite" \
		"$POSTRECEIVE_HOOK"

	sed -i "s#/path/to/sync-script#${SYNCHRONIZE_SCRIPT}#" "$POSTRECEIVE_HOOK"
	sed -i "s#other-remote#${CONF_OTHER_REMOTE}#" "$POSTRECEIVE_HOOK"

	echo "Testing $CONF_OTHER_REMOTE post-receive hook"
	echo a b master | "$POSTRECEIVE_HOOK"

	echo "Setting up $CONF_OTHER_REMOTE post-receive hook: SUCCESS"
}

function announce_success()
{
	echo '---'
	echo "Satellite repository for two-way mirroring between"
	echo "    origin: ${CONF_ORIGIN_URL}"
	echo "and"
	echo "    ${CONF_OTHER_REMOTE}: ${CONF_OTHER_URL}"
	echo "successfully set up in"
	echo "    ${CONF_GITDIR}"
	echo
	echo "$CONF_OTHER_REMOTE post-receive hook has been set up in"
	echo "    ${POSTRECEIVE_HOOK}"
}

function print_cron_job_to_push_changes_from_origin_to_other()
{
	echo '---'
	echo 'Finally, enable scheduled job with the following command:'
	echo
	echo "sudo sh -o noglob -c 'echo \"*/$CONF_FREQUENCY * * * *  git  $SYNCHRONIZE_SCRIPT\" >> /etc/crontab'"
}

setup_satellite_repository
setup_postreceive_hook_to_push_changes_from_other_to_origin
announce_success
print_cron_job_to_push_changes_from_origin_to_other
