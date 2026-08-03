# Docker Control Center

A Docker dashboard for the terminal. Bash and `make`, no daemons, nothing
resident.

It shows you at a glance which containers you have, grouped by project, how much
CPU and RAM they use, which volumes and images take up disk, and how much junk
you can delete. And it lets you operate: start, stop, tail logs, get a shell,
back volumes up, clean.

```bash
make dash
```

## Why not `lazydocker`?

Because they solve different problems.

| | |
|---|---|
| **`lazydocker`, `ctop`, `dry`** | Interactive interfaces. You open them, look, navigate, quit. Go binaries you have to install. |
| **This** | Commands that print and exit. Nothing to install: bash and `make`, which you already have. |

Three differences that matter depending on what you need:

- **It fits in a script.** `make status` prints and exits, so it works inside a
  `watch`, a cron job or a pipe. A TUI does not.
- **Nothing to install on a server.** A `git clone` or a 100 KB file. No
  binaries, no package manager, no root.
- **The numbers are verifiable.** Docker's `Reclaimable` field does not add up
  with the containerd snapshotter: `SharedSize` comes back as 0 for images that
  *do* share base layers. Nothing here is estimated — everything is counted from
  the raw API fields, and the code documents where each figure comes from.

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
  container, volume or stack. Get a name wrong and it suggests the closest one.
- **Backs volumes up.** One command to save them, another to restore them.
- **Speaks your language.** English and Spanish, detected from your
  environment. Nothing to configure.

## Getting started

```bash
curl -LO https://github.com/velezanthony/docker-control-center/releases/latest/download/dcc
chmod +x dcc && mv dcc ~/.local/bin/
dcc dash
```

One file, ~100 KB. See [Installation](users/installation.md) for the other way
(cloning the repository) and the requirements.
