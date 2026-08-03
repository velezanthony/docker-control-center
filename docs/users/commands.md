# Commands

Run `make` (or `dcc`) with no arguments and you get the full list with
descriptions. This page explains the ones that need it.

Every command that needs a name **opens a menu** if you do not give it one:

=== "Repository"
    ```bash
    make logs              # menu to pick
    make logs C=api        # straight to it
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
| `dash-fast` | Same without sizes — always ~1 s |
| `status` | Executive summary: counted junk plus real disk usage |
| `ps` | Containers grouped by stack, coloured by severity |
| `ram` | RAM used by the engine, read from `/proc` |

### Reading the colours

The colour of a stopped container encodes **severity**, not just liveness:

| | |
|---|---|
| Grey `▹` | Exited with code 0 — a clean stop |
| Yellow `▹` | Exited 137 — SIGKILL, OOM, or a stop that timed out |
| Red `▹` | Any other code — it died badly |

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
    `volume-backup` writes the **entire contents** of your volumes to
    `./backups` — databases included. That folder is in `.gitignore` for that
    reason. To keep them outside the repository:

    ```bash
    BACKUP_DIR=/safe/path make volume-backup-all
    ```

`volume-restore` **verifies the tar before deleting anything**. A corrupt backup
does not destroy the volume.

## Cleanup

`clean` (safe), `clean-build` (build cache), `clean-hard` (asks for written
confirmation), `rm-image`

None of them touch volumes. Ever.

## Exit codes

The tool is chainable, so the codes mean something:

| | |
|---|---|
| `0` | Done, **or** the system was already in that state |
| `1` | What you named does not exist |
| `2` | Usage error, or a missing value with no terminal to ask on |

The distinction that matters is *"already like that"* versus *"does not exist"*.
A typo has to fail; a no-op does not.

```bash
make stack-start S=api && ./deploy.sh   # only deploys if api really started
```
