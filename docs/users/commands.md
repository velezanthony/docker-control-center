# Commands

In the repository the product commands go through `make run` — the Makefile only
has development targets. `make dev <command>` rebuilds the single file first.
Run `dcc` with no arguments and you get the full list with descriptions. This
page explains the ones that need it.

Every command that takes a name **opens a menu** if you do not give it one —
on a terminal. With no TTY it prints the candidates on stderr and exits `2`
instead of hanging. `dex` is the exception: it never opens a menu, and with no
name it lists the running containers and exits `2`.

=== "Repository"
    ```bash
    make run logs          # menu to pick
    make run logs api      # straight to it
    ```

=== "Single file"
    ```bash
    dcc logs               # menu to pick
    dcc logs api           # straight to it
    ```

## Overview

| | |
|---|---|
| `dash` | The full panel: junk, alerts, stacks, volumes, images, disk |
| `dash-fast` | Same without the size and disk queries — the fast path |
| `status` | Executive summary: counted junk plus real disk usage |
| `ps` | Containers grouped by stack, coloured by severity |
| `ram` | RAM used by the engine, read from `/proc` |

`dash-fast` is fast because it skips the size and disk queries, not because it
takes a fixed time: it still lists and inspects every container, so it grows
with how many you have and with the latency of the daemon you are pointed at.
The built-in help still says `always ~1s`; there is no measurement behind that
number.

### Reading the colours

The colour of a stopped container encodes **severity**, not just liveness:

| | |
|---|---|
| Grey `▹` | Exited with code 0 — a clean stop, **or** no exit code to read |
| Yellow `▹` | Exited 137 — SIGKILL, OOM, or a stop that timed out |
| Red `▹` | Any other code — it died badly |

That last case is the one to watch. The severity comes from parsing
`Exited (N)` out of the status line, so a container sitting in `Restarting (1)`,
`Created` or `Paused` has no code to read and gets exactly the same grey as a
clean stop: a crash loop looks like a tidy shutdown. The alerts section reads
the same field, so it misses it too.

The CPU column shows a percentage **of one core**: 100% means one full core, so
a container using two shows 200%.

## Stacks

`stack-start`, `stack-stop`, `stack-restart`, `stack-logs`, `stack-rm`

!!! info "Why not `up` and `down`"
    In compose, `up` and `down` mean CREATE and DESTROY. These only start and
    stop containers that already exist. Calling them `up` would be lying. To
    create a stack from scratch you need its compose file — go to the project
    directory.

Containers are found **by label**, not with `docker compose -p`: VS Code
devcontainers record paths to ephemeral YAML files that VS Code then deletes, so
any `docker compose` against them fails. The project label is always there.

## Volumes

`volume-inspect`, `volume-tree`, `volume-backup`, `volume-backup-all`,
`volume-restore`, `volumes-orphan`

!!! warning "About backups"
    `volume-backup` writes the **entire contents** of your volumes — databases
    included — to a `backups/` directory **next to the tool**, not next to your
    shell. In the repository that is `backups/`, which is in `.gitignore` for
    that reason; installed as a single file in `~/.local/bin`, it is
    `~/.local/backups`. To choose the place yourself:

    ```bash
    BACKUP_DIR=/safe/path dcc volume-backup-all
    ```

    Two things the green ✓ does not tell you. The tar is taken **hot** —
    nothing is stopped and nothing checks whether the volume is in use — so a
    live Postgres or MySQL can come out inconsistent and fail to restore, with
    a ✓ identical to a good one. And the destination is always
    `<name>.tar.gz`, so a second backup **overwrites** the previous one: no
    versioning, no warning. (A backup that fails is discarded before that, so
    it never destroys the copy you already had.)
    [Limitations](limitations.md#backups-read-this-before-you-trust-them)
    covers the rest, including the helper container.

!!! danger "`volume-restore` deletes without asking"
    It is the most destructive command in the tool — it wipes the volume's
    contents from inside a container — and it asks **nothing**: no
    confirmation, no `DANGER:` mark in its help line, and no check that the
    volume is mounted. Docker will mount it a second time, so you can replace
    the data underneath a running process.

    It also **cannot restore a volume you deleted**, which is the disaster a
    backup exists for. The name is validated against `docker volume ls -q`
    first, so a volume that is gone gets `There is no volume called 'X'` on
    stderr and exit `1` while the intact tarball sits in the backup directory.
    Recreate it and the restore works:

    ```bash
    docker volume create myvol && dcc volume-restore myvol
    ```

    What it checks before deleting is `gzip -t` on the backup — the **gzip
    wrapper**, not that the tar inside is complete. It unpacks into a
    `.dcc-restore` directory inside the volume and only then wipes the old
    contents, so it needs roughly twice the volume's size free, and an
    interrupt between the two halves leaves the volume half written with that
    directory still in it. The backup itself is never touched.

## Cleanup

`clean` (safe), `clean-build` (build cache), `clean-hard` (asks for written
confirmation), `rm-image`

None of them touch volumes. Ever. That is all "safe" means: `clean` still
deletes every stopped container on the machine, with its writable layer, and it
does not ask. Of everything in the tool that destroys or stops something, only
`stack-rm` and `clean-hard` ask first —
[Limitations](limitations.md#commands-that-destroy-things) has the table.

## Exit codes

The tool is chainable, so the codes mean something:

| | |
|---|---|
| `0` | Done, **or** the system was already in that state |
| `1` | What you named does not exist, or the operation did not go through |
| `2` | Usage error, no terminal to ask on, an unwritable `backups/`, no `jq` |
| `3` | Cancelled by whoever ran it, **from a pick menu** |

Two distinctions matter. *"Already like that"* versus *"does not exist"*: a typo
has to fail, a no-op does not. And `3` versus `2`: a wrapper script needs to tell
its own bug from a human saying no.

Both have holes. `stop` and `sh` resolve the name against the **running**
containers only, so a container that exists but is stopped answers
`There is no running container called 'X'` and exits `1`: the message is false,
and `stop` is not idempotent — the second call fails as if you had made a typo.
`start`, `restart`, `logs`, `tail` and `inspect` use `docker ps -a` and behave
as the table says. And `2` is broader than "you called it wrong": it is also
what `volume-backup` returns when `BACKUP_DIR` is not writable, and what
`inspect` and `volume-inspect` return when `jq` is missing.

```bash
dcc stack-start api && ./deploy.sh   # only deploys if api really started
```

!!! warning "`make run` swallows the exit code"
    In the repository, `run` and `dev` end in `|| true` so that a `2` from the
    tool is not read by make as a broken recipe. That means `make run` always
    exits `0`. Chain the single file, never `make run`.

!!! warning "Written confirmations do not return `3`, and auto-deny with no TTY"
    `stack-rm` and `clean-hard` ask you to type a word out, and saying no exits
    `0` — so `dcc clean-hard && ...` carries on. Only the pick menu returns `3`.

    Worse without a terminal. `confirm()` never checks for one, so in a script,
    a cron job or CI the question is never even shown: the read fails, the
    empty answer does not match the word, and the command returns `0` having
    done nothing and having said nothing about it. See
    [Limitations](limitations.md#written-confirmations-auto-deny-without-a-terminal).
