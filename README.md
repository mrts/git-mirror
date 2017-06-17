# git-mirror

Scripts for setting up and synchronizing **two-way** mirroring between Git
repositories. There are instructions for one-way mirroring below as well.

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

Synchronizes the mirror that was previously set up with
`scripts/setup-git-mirror.sh`.

This script will be run both from the mirror repository `post-receive` hook
and `crontab`.

There's locking to assure that two script runs don't step on each other's toes.

## Logs

Synchronization logs are written to `scripts/synchronize-git-mirror.log*`.

## Configuration

Configuration is in `scripts/synchronize-git-mirror.config`, see comments there.

## One-way mirroring

Simple one-way mirroring setup:

    +------------+          +------------+           +------------+
    |            |          |            |           |            |
    | Source     |          | Mirror     |           | Target     |
    | repository <-- pull --+ repository +-- push ---> repository |
    |            |          |            |           |            |
    +------------+          +------------+           +------------+

Steps:

1. Add system user, generate key, share the key with source repository owner:

       sudo adduser --system gitmirror
       sudo -u gitmirror ssh-keygen
       sudo cat /home/gitmirror/.ssh/id_rsa.pub
        
2. Test that cloning works:

       cd /tmp && sudo -u gitmirror git clone git@source-repository.com:example/example.git

3. Create mirror repository:

       sudo -u gitmirror mkdir example-mirror && cd example-mirror
       sudo -u gitmirror git clone --mirror git@source-repository.com:example/example.git
       cd example.git/
       sudo -u gitmirror git remote add --mirror=push target git@target-repository.com:example/example-mirror.git

4. Create synchronization script, test:

       cat <<EOF > /tmp/mirror-example.sh
       #!/bin/bash
       cd /home/gitmirror/example-mirror/example.git/
       git fetch --prune origin
       git push --mirror target
       EOF
       chmod 755 /tmp/mirror-example.sh
       sudo -u gitmirror cp -a /tmp/mirror-example.sh /home/gitmirror/example-mirror/mirror-example.sh
       
       sudo -u gitmirror /home/gitmirror/example-mirror/mirror-example.sh
       
5. Add synchronization script to `/etc/crontab` (with e.g. 30-minute interval):

       */30 * * * *  gitmirror  /home/gitmirror/example-mirror/mirror-example.sh

## GitLab

GitLab repositories that need two-way synchronization with an origin repository
need a different setup.

As GitLab uses hooks to track changes in repositories, a separate satellite
repository is needed for two-way mirroring that fetches from the origin
repository and pushes to GitLab and vice-versa.

In the following, GitLab Omnibus installation is assumed.

### Setup satellite repository for mirroring

1. Login as the GitLab `git` user in the GitLab server, generate SSH key:

        sudo su git
        ssh-keygen

2. Create a dedicated GitLab mirroring account in GitLab web interface,
   upload the SSH public key into the account profile.

3. Create the mirror project in GitLab web interface, give _Master_ access to
   the mirroring account.

4. Copy the SSH public key to origin repository SSH authorized keys:

        scp ~/.ssh/id_rsa.pub user@origin-repository-host:
        ssh user@origin-repository-host
        cat id_rsa.pub >> ~/.ssh/authorized_keys
        logout

5. _(Optional)_ If origin repository username differs from `git`, setup SSH
   host alias:

        cat >> ~/.ssh/config << EOT
        Host gitmirror-origin-host
        User user
        HostName origin-repository-host
        EOT

6. Assure SSH server accepts connections to `localhost` in GitLab server.

7. Setup the mirroring tools workspace for `git` user and configure `git-mirror`:

        sudo mkdir /var/opt/gitlab/mirroring-tools
        sudo chown git: /var/opt/gitlab/mirroring-tools
        sudo su git
        cd ~/mirroring-tools
        mkdir utils

        cd utils
        git clone https://github.com/mrts/git-mirror.git
        cd git-mirror/scripts/satellite

        # change the substituted values below according to your needs
        sed -i 's#CONF_ORIGIN_URL=.*#CONF_ORIGIN_URL=origin-repository-host:git/repo.git#' \
            synchronize-git-repositories-with-satellite.config
        sed -i 's#CONF_OTHER_URL=.*#CONF_OTHER_URL=localhost:mirror/repo.git#' \
            synchronize-git-repositories-with-satellite.config
        sed -i 's#CONF_GITDIR=.*#CONF_GITDIR=/var/opt/gitlab/mirroring-tools/repo.git#' \
            synchronize-git-repositories-with-satellite.config
        sed -i 's#CONF_OTHER_GITDIR=.*#CONF_OTHER_GITDIR=/var/opt/gitlab/git-data/repositories/mirror/repo.git#' \
            synchronize-git-repositories-with-satellite.config

8. Run the setup script:

        ./setup-synchronize-git-repositories-with-satellite.sh

    * The setup script does the following:

        1. Sets up the satellite repository with origin and GitLab remotes
        2. Sets up the `post-receive` hook in GitLab repository to push changes
        from GitLab to origin
        3. Prints the line that should be added to `crontab` for running the
        synchronization job.

    * Assure passwordless access works, no password propmts should appear
    during setup.

9. Add the line that was printed in the end of setup scrip run to `crontab`:

        sudo sh -o noglob -c 'echo "*/1 * * * *  git  ...path..." >> /etc/crontab'

10. Test and examine logs.

    1. Verify that all branches are present and contain right commits in GitLab.
    2. Create a merge request and merge it in GitLab, verify that merge is
    mirrored to origin immediately.
    3. Commit to any branch in origin, verify that change is mirrored in GitLab 
    after cron has run.
    4. Rewrite `master` history and delete `master` in GitLab, verify that this 
    does *not* get through to origin and results in error in logs.
    5. Delete and create any other branch in GitLab, verify that delete and
    create is mirrored to origin immediately.
    6. Delete and create branches in origin, verify that change is mirrored in
    GitLab after cron has run.

11. Rejoice :)!

### Caveats

It seems that deleting and creating branches from the GitLab web UI does not
trigger the `post-receive` hook in GitLab, so deleted branches will be
resurrected during next update from origin. This problem has been filed as
[bug #1156](https://gitlab.com/gitlab-org/gitlab-ce/issues/1156) in the GitLab
issue tracker.
