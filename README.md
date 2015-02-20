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

To setup a mirror repository in GitLab (Omnibus installation is assumed),
proceed as follows:

1. Create the project in GitLab web interface and, if possible, import it with
   the _Import existing repository by URL_ link (to get initial branches etc):

2. _(Optional)_ If automatic import is not possible, import with GitLab shell:

        su git
        /opt/gitlab/embedded/service/gitlab-shell/bin/gitlab-projects \
            rm-project <group>/<project>.git
        /opt/gitlab/embedded/service/gitlab-shell/bin/gitlab-projects \
            import-project <group>/<project>.git ssh://<origin>/<project>.git

3. Setup mirroring with `scripts/setup-git-mirror.sh`:

        cd /path/to/repositories/<group>
        edit /path/to/scripts/synchronize-git-mirror.config
        rm -rf <project>.git
        /path/to/scripts/setup-git-mirror.sh

4. Setup GitLab hooks, preserving the custom `post-receive` hook:

        cd <project>.git
        mkdir custom_hooks
        mv hooks/post-receive custom_hooks
        rm -r hooks
        ln -s /opt/gitlab/embedded/service/gitlab-shell/hooks .

5. **Unfortunately, this is not currently sufficient to get remote branches
   into GitLab.** The problem is that `git remote update` does not trigger any
   hooks, and thus GitLab is not notified about new tags and branches in the
   repository.
