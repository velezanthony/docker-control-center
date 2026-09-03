# Installation

## Cloning the repository

Today this is the only way: the repository carries no tags, so `releases/latest`
has nothing to serve yet.

```bash
git clone https://github.com/velezanthony/docker-control-center
cd docker-control-center
make link
```

`make link` symlinks the build into `~/.local/bin`, so a later `make bundle`
updates `dcc` on its own.

That symlink is **absolute** and points inside the clone
(`<clone>/dist/docker-control-center.sh`). Move the clone, rename it or delete
it and `dcc` becomes a dangling link that dies with *"No such file or
directory"* — running `make link` again from the new location is the fix. The
destination directory is `LINK_DIR` if you set it; if it is not on your `PATH`,
`make link` says so and tells you what to add.

`make` with no arguments prints the **development** targets — the Makefile has
no product commands. For the command list, run `dcc` (or `make run`) with no
arguments.

## One file

From the first release on:

!!! warning "It does not work today, and it fails quietly"
    With no tags there is nothing behind `releases/latest`. The URL answers
    `404`, and `curl -LO` does not treat that as an error: checked today, it
    writes a 9-byte file called `dcc` whose contents are `Not Found` and exits
    `0`. The next two lines then make that file executable and put it on your
    `PATH`. Add `-f` if you want `curl` to fail loudly.

```bash
curl -LO https://github.com/velezanthony/docker-control-center/releases/latest/download/dcc
chmod +x dcc && mv dcc ~/.local/bin/
dcc dash
```

An executable under 90 KB. Nothing to install: it carries both languages and
everything of its own inside. What it does not carry are the system utilities
under Requirements. Nothing will verify the download for you either — no
sha256, no signature ([Limitations](limitations.md#not-released-yet)).

!!! note "The helper image"
    The first time you use `volume-tree`, `volume-backup`, `volume-backup-all`
    or `volume-restore`, Docker will pull the `alpine` image — 3.9 MB to download, 13 MB on disk,
    measured with `docker image ls` on amd64. It is what runs inside the volume.
    You can change it with `HELPER_IMAGE=busybox`.

## Requirements

**Required.** This is the short list;
[Limitations](limitations.md#what-it-needs) has the complete one, including two
hard dependencies whose absence produces a message that blames the wrong thing.

- **Native Docker Engine**, with the socket readable by your user
- **bash 4 or newer** (associative arrays)
- **`$HOME` or `$XDG_CONFIG_HOME` defined**. The path to the config file is
  resolved at startup under `set -u`, so with neither of them set the tool dies
  on a raw `HOME: unbound variable` and exit `1` before printing a word of its
  own — `dcc version` included. It bites in cron jobs, systemd units, `env -i`
  and minimal CI containers, where the environment is not the one your shell
  gives you
- **awk** — any. The code deliberately avoids GNU extensions, so it works the
  same with `mawk` (Debian, Ubuntu) as with `gawk` (Fedora, Arch)
- The usual **POSIX utilities**: `sed`, `grep`, `sort`, `tr`, `cut`, `paste`,
  `wc`, `du`, `xargs`. They ship with any Linux; they are listed for honesty,
  not because you need to install them

**Recommended.** Missing one of these does not break the tool, but only the
first two tell you they are missing; the rest keep quiet and go on.

| Missing | What you lose |
|---|---|
| `curl` | Sizes. The dashboard falls back to fast mode and shows no disk or junk. It warns |
| `jq` | The same, **and** `inspect` and `volume-inspect` stop working. It warns |
| `tput` | Terminal width detection; assumes 100 columns. Silent |
| `systemctl` | The `engine` command, which does not degrade — it lies. It asks systemd instead of Docker, so with a perfectly healthy daemon it prints `○ dockerd stopped` **and** `does NOT start on boot`, and nothing says `systemctl` is what is missing. Verified today on this machine ([Limitations](limitations.md#engine-asks-systemd-not-docker)) |
| `getconf` | Nothing you can see: the memory page size is assumed to be 4096, so on a 16 KB or 64 KB page kernel every RAM figure is off by that factor |

```bash
sudo apt install jq curl        # Debian / Ubuntu
sudo dnf install jq curl        # Fedora / RHEL
sudo pacman -S jq curl          # Arch
```

To use Docker without `sudo`:

```bash
sudo usermod -aG docker $USER   # log out and back in
```

## Systems

| | |
|---|---|
| **Any Linux distro** | Debian, Ubuntu, Fedora, RHEL, Arch, openSUSE… |
| **Alpine** | Untested. You would need to install `bash`, and with OpenRC instead of systemd `engine` will report a stopped daemon on a running one |
| **macOS** | No. It ships bash 3.2 and there is no native Docker Engine |
| **Windows** | No |

Developed and tested on Ubuntu, but it depends on nothing Ubuntu-specific. It
does not need `procps`: the engine's RAM is read from `/proc` in pure bash.

## Checking your installation

```bash
dcc version
```

```
Docker Control Center 0.9.0
  bash     5.2.21
  docker   /usr/bin/docker
  jq       not installed
  curl     /usr/bin/curl
  awk      /usr/bin/awk
  tput     /usr/bin/tput
  language en (locale)
  config   /home/you/.config/dcc/config
```

That is the first thing to look at when something behaves oddly, and the first
thing you will be asked for if you open an issue. Note what it does not check:
`gzip`, `mktemp`, `getconf` and `systemctl` are absent from that list, and they
are the ones whose absence produces the most confusing failures
([Limitations](limitations.md#dcc-version-does-not-cover-the-confusing-cases)).

## Uninstalling

There is no `make uninstall` and no `dcc uninstall`. Removing it is done by
hand, and these are the files it leaves behind:

```bash
rm ~/.local/bin/dcc              # the symlink (or the copied executable)
rm -rf ~/.config/dcc             # only exists if you ran `dcc lang`
docker image rm alpine           # the helper image, if you used volume-*
```

Your backup tarballs are **not** in any of those places: they sit next to the
directory the tool runs from — `~/.local/backups` with the install above —
unless you set `BACKUP_DIR`. Check before you delete anything, and see
[Limitations](limitations.md#where-they-land-is-probably-not-where-you-expect).

If you cloned the repository, deleting the clone takes the rest with it:
`dist/`, and `vendor/`, `coverage/` and the `.git/hooks/pre-commit` that
`make deps`, `make coverage` and `make hooks` create.
