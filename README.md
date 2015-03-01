# git-mirror

Scripts for setting up and synchronizing two-way mirroring between Git repositories.

## `scripts/setup-git-mirror.sh`

Sets up a remote Git repository mirror.

**Warning: mirroring may destroy revisions in either repository.**

`git clone --mirror` implies `--bare` and sets up the origin remote so that
`git fetch` will directly fetch into local branches without merging.
It will force the update, so if remote history has diverged from local,
local changes will be lost.

`git push --mirror` is similar: instead of pushing just a branch, it assures
that all references (branches, tags etc) are the same on the remote
end as they are in local, even if this means forced updates or deletion.

**It is strongly recommended to protect important branches and tags in the
remote mirror against unintended modification with with a Git update hook,
see example in `scripts/git-update-hook-for-protecting-branches-and-tags`.**
Copy it to `hooks/update` and make it executable with `chmod 755 hooks/update`
in the remote repository.

## `scripts/synchronize-git-mirror.sh`

Synchronizes the mirror that was previously set up with `scripts/setup-git-mirror.sh`.

This script will be run both from the mirror repository `post-receive` hook
and `crontab`.

There's locking to assure that two script runs don't step on each other's toes.

## Logs

Synchronization logs are written to `scripts/synchronize-git-mirror.log*`.

## Configuration

Configuration is in `scripts/synchronize-git-mirror.config`, see comments there.

## GitLab

GitLab repositories that need two-way synchronization with an upstream repository
need a different setup.

As GitLab uses hooks to track changes in repositories, a separate satellite repository
is needed for two-way mirroring that fetches from the origin repository and pushes
to GitLab and vice-versa.

In the following, GitLab Omnibus installation is assumed.

### Setup satellite repository for mirroring

1. Login as the GitLab `git` user, generate SSH key:

        sudo su git
        ssh-keygen

2. Create a dedicated GitLab account for mirroring in GitLab web interface,
   upload the SSH public key into the account profile.

3. Create the mirror project in GitLab web interface, give _Master_ access to
   the mirroring account.

4. Copy the SSH public key to upstream repository SSH authorized keys:

        scp ~/.ssh/id_rsa.pub user@origin-repository-host:
        ssh user@origin-repository-host
        cat id_rsa.pub >> ~/.ssh/authorized_keys
        logout

5. _(Optional)_ If origin repository username differs from `git`, setup SSH host alias:

        cat >> ~/.ssh/config << EOT
        Host gitmirror-origin
        User user
        HostName upstream-repository-host
        EOT

6. Assure SSH server accepts connections to `localhost` in GitLab server.

7. Setup the mirroring tools workspace for `git` user and configure `git-mirror`:

        mkdir ~/mirroring-tools
        cd ~/mirroring-tools
        mkdir mirror-repo utils

        cd utils
        git clone https://github.com/mrts/git-mirror.git
        cd git-mirror

        # change the substituted values below according to your needs
        sed -i 's#CONF_UPSTREAM_URL=.*#CONF_UPSTREAM_URL=origin-repository-host:git/repo.git#' \
            scripts/synchronize-git-mirror.config
        sed -i 's#CONF_OTHER_URL=.*#CONF_OTHER_URL=localhost:mirror/repo.git#' \
            scripts/synchronize-git-mirror.config
        sed -i 's#CONF_GITDIR=.*#CONF_GITDIR=/var/opt/gitlab/mirroring-tools/repo.git#' \
            scripts/synchronize-git-mirror.config
        sed -i 's#CONF_OTHER_GITDIR=.*#CONF_OTHER_GITDIR=/var/opt/gitlab/git-data/repositories/mirror/repo.git#' \
            scripts/synchronize-git-mirror.config

8. Setup mirror, do initial import to GitLab repository, test two-way synchronization:

        source scripts/synchronize-git-mirror.config

        git clone --mirror $CONF_UPSTREAM_URL $CONF_GITDIR
        cd $CONF_GITDIR
        git config --unset remote.origin.mirror # can't push refs with mirror

        git remote add --mirror $CONF_OTHER_REMOTE $CONF_OTHER_URL
        git config --unset remote.$CONF_OTHER_REMOTE.mirror

        # origin -> gitlab
        git remote update --prune origin
        git push --mirror --prune $CONF_OTHER_REMOTE

        # gitlab -> origin
        git remote update --prune $CONF_OTHER_REMOTE
        git push --mirror --prune origin

    * Assure passwordless access works, no password propmts should appear above.

### Setup post-receive hook to push changes from GitLab to origin

    # test synchronization from origin to gitlab
    scripts/synchronize-git-repositories-with-mirror-satellite-repository.sh
    # test synchronization from gitlab to origin
    scripts/synchronize-git-repositories-with-mirror-satellite-repository.sh $CONF_OTHER_REMOTE

    mkdir $CONF_OTHER_GITDIR/custom_hooks
    cp -a scripts/git-post-receive-hook-for-updating-satellite-repository \
        $CONF_OTHER_GITDIR/custom_hooks/post-receive

    sed -i "s#/path/to/git-mirror#`pwd`#" $CONF_OTHER_GITDIR/custom_hooks/post-receive
    sed -i "s#other-remote#${CONF_OTHER_REMOTE}#" $CONF_OTHER_GITDIR/custom_hooks/post-receive

    # test the script
    $CONF_OTHER_GITDIR/custom_hooks/post-receive

### Setup cron job to push changes from origin to GitLab

    echo '---'
    echo 'Setup successful, now enable scheduled job with the following command:'
    echo
    echo "sudo sh -o noglob -c 'echo \"*/1 * * * *    git    `pwd`/scripts/synchronize-git-repositories-with-mirror-satellite-repository.sh\" >> /etc/crontab'"