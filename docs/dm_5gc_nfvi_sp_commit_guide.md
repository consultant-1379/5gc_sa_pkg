# DM 5GC on NFVI SP commit guidelines
The contents on this page should give information about DM 5GC NFVI SP
commit guidelines and the steps required to get started with contributing to
the development of Target Solution NFVI track.
---
## Follow the below steps to push your commit to SP.

---
**NOTE**

If you are working within a existing local git repo which has pushed to remote
and merged, then you need to run `git pull --rebase` first and continue to your
commit work. Otherwide the new commit will be based on this local latest commit
instead of remote latest commit.

Gerrit server requires SSH connection. Therefore, it is required to
generate a public SSH key and add it to your user profile in Gerrit.
Follow the instructions to [**set up the access to Gerrit**][1]
and to [**verify that the connection is working**][2].

Once you have a working SSH connection to Gerrit do the following which
will do a `git clone` of the BCAT repository and fetch the hooks from
the Gerrit server.


---

1. Clone working branch from remote
    ```
    $ git clone -b <branch> ssh://$USER@gerrit.ericsson.se:29418/5gc_config/5gc_sa_pkg && scp -p -P 29418 $USER@gerrit.ericsson.se:hooks/commit-msg 5gc_sa_pkg/.git/hooks/
    $ cd 5gc_sa_pkg
    ```
2. There are some parameters that are required to set before you can start doing all git operations to gerrit. First you will need to set name and email in your git configuration. Ignore this step if you have already configured it
   ```
   $ git config --global --add user.email firstname.lastname@ericsson.com
   $ git config --global --add user.name "Firstname Lastname"
   ```

3. After changes, cd to local git repo root directory and perform the below git cmds to commit your work
   ```
   $ git add .
   $ git rm XXX          # if needed
   $ git status -s       # it is ok if no prompt, otherwide, repeat above steps
   $ git commit -a       # newly commit your work and add comments
   $ git commit --amend  # commit your work as patch to current local latest commit
   $ gitpush             # use `gitpush` cmd to push your work instead of 'git push ...'
   ```
4. At least one reviewer should review your commit and given +1, then the commit can be merged

## Introduction of `gitpush` command.

---
**NOTE**

`gitpush` will do:
- run `git status` to check if local git repo is clean before push
- run `git pull --rebase` before push
- run `pytest` for tests directory before push if test case exists in tests directory
- run `git push ...` to push current branch when above steps are OK

---
  ```
  $ gitpush -h                                                   # print help info
  $ gitpush -r wallance.hou@ericsson.com,ken.shi@ericsson.com    # push to remote with adding reviewer
  $ gitpush --pytest-only                                        # only run pytest
  $ gitpush --pytest-trace                                       # corresponding to pytest option --full-trace
  $ gitpush -y                                                   # push to remote without prompt
  ```

## SP specific information

### Change-Id
Gerrit depends on `Change-Id` annotations in your commit message.
If you try to push a commit without one, it will explain how
to install the proper git-hook.

### Commit messages
When writing commit messages, it is important to follow the
[**PDU-PC Git and Gerrit User Guidelines**][3]. Keep the commit messages
well formatted and be as descriptive as you possibly can so that others
understand what changes you have made.

a. There must have one empty line between title and body message
b. Do not input too long title message (better less than 70)
c. Do not input too long line for body message (better less than 70)

Here is the example commit message:

```
Author: Shujun Chen <shujun.chen@ericsson.com>
Date:   Mon Jul 18 04:53:30 2022 +0200

    update N99 PCC CCDM CCRC PCG configuration and values files

    1. For PCG
       update software version for PCG 1.14

    2. For CCDM
       update software version for CCDM 1.7

    3. For CCRC
       update software version for CCRC 1.8
       update values file according to CCRC 1.8 template

    4. For PCC
       update software version for PCC1.22
       update vpngw interface configuration according to NIR
       update smf nsmf service configuration for values file accord to NIR

    Change-Id: I05360860414cebb3f036f608fcbe7cda53e975e4
```

[1]: https://pdupc-confluence.internal.ericsson.com/display/PCCPC/PDU-PC+Git+and+Gerrit+workflow#PDU-PCGitandGerritworkflow-3.2.5SetupSSHauthenticationtoGerritCentral
[2]: https://pdupc-confluence.internal.ericsson.com/display/PCCPC/PDU-PC+Git+and+Gerrit+workflow#PDU-PCGitandGerritworkflow-3.2.6VerifySSHconnectiontoGerritCentral
[3]: https://pdupc-confluence.internal.ericsson.com/display/PCCPC/PDU-PC+Git+and+Gerrit+Design+Rules#PDU-PCGitandGerritDesignRules-4.2Commitmessage
