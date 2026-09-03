# Docker Control Center

A Docker dashboard for the terminal. One bash file, no daemons, nothing
resident.

It shows you at a glance which containers you have, grouped by project, how much
CPU and RAM they use, which volumes and images take up disk, and how much junk
you can delete. And it lets you operate: start, stop, tail logs, get a shell,
back volumes up, clean.

```bash
dcc dash
```

## Why not `lazydocker`?

Because they solve different problems.

| | |
|---|---|
| **`lazydocker`, `ctop`, `dry`** | Interactive interfaces. You open them, look, navigate, quit. Go binaries you have to install. |
| **This** | Commands that print and exit. One bash file: `docker`, `bash` 4+ and `awk`, which you already have. |

Three differences that matter depending on what you need:

- **It fits in a script.** `dcc status` prints and exits, so it works inside a
  `watch`, a cron job or a pipe. A TUI does not. Call the file, not `make run`,
  which always exits `0` — see [Exit codes](users/commands.md#exit-codes). The
  colour escapes travel down the pipe with the output: there is no `NO_COLOR`
  and no pipe detection.
- **Nothing to install on a server.** A `git clone` or a single file under
  90 KB. No binaries, no package manager, no root.
- **The numbers are verifiable.** Docker's `Reclaimable` field does not add up
  with the containerd snapshotter: `SharedSize` comes back as 0 for images that
  *do* share base layers. The disk figures are not estimated — they are counted
  from the raw API fields, and the code documents where each one comes from.

If what you want is to browse containers with the keyboard, use `lazydocker`:
it is better at that and we are not competing.

## Who it is for

People running **native Docker Engine on Linux**: the daemon as a system
service, no Docker Desktop in the middle.

That is the scenario of a **server** or a **Linux development machine**, where
there is no desktop environment — or where you simply do not want a desktop
application eating memory just to show you a list of containers.

If you use Docker Desktop, this tool is not for you: you already have that
interface.

## What it does

- **Shows the real state.** Containers by stack, coloured by severity: grey if
  it stopped cleanly, yellow if it was killed, red if it died with an error.
- **Tells you what takes up disk.** Sizes counted from the API, not estimated.
  It tells you how much you would reclaim and with which command.
- **Operates without memorising names.** Commands open a menu to pick the
  container, volume or stack. Get a name wrong in `dex` and it suggests the
  closest one.
- **Backs volumes up.** One command to save them, another to restore them. They
  are taken hot, each one overwrites the previous, and `volume-restore` needs
  the volume to still exist — read
  [Limitations](users/limitations.md#backups-read-this-before-you-trust-them)
  before you rely on them.
- **Speaks your language.** English and Spanish, detected from your
  environment. Nothing to configure.

## Getting started

!!! warning "Nothing has been released yet"
    The repository carries no tags, so `releases/latest` has nothing to serve.
    Until the first one, clone the repository and run `make link`.

```bash
git clone https://github.com/velezanthony/docker-control-center
cd docker-control-center && make link
dcc dash
```

From the first release on it is one file, under 90 KB:

```bash
curl -LO https://github.com/velezanthony/docker-control-center/releases/latest/download/dcc
chmod +x dcc && mv dcc ~/.local/bin/
```

See [Installation](users/installation.md) for the requirements, and
[Limitations](users/limitations.md) for what it does not do, does badly, or does
quietly.
