#!/bin/bash

# Setup two-way Git mirror with a remote repository.
#
# See ../README.md for details.

set -u
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SYNCHRONIZE_SCRIPT="$SCRIPT_DIR/synchronize-git-mirror.sh"
CONFIGFILE="$SCRIPT_DIR/synchronize-git-mirror.config"

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

git clone --mirror $CONF_UPSTREAM_URL "$CONF_GITDIR"

pushd "$CONF_GITDIR"

echo "$SYNCHRONIZE_SCRIPT" '$1' > hooks/post-receive
chmod 755 hooks/post-receive

popd

echo "Mirror for ${CONF_UPSTREAM_URL} successfully set up in ${CONF_GITDIR}."
echo "Run the following next to add synchronize-git-mirror.sh to crontab:"
echo "sudo sh -c 'echo \"*/$CONF_FREQUENCY * * * *    git    $SYNCHRONIZE_SCRIPT\" >> /etc/crontab'"
