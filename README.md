# Docker Control Center

A Docker dashboard for the terminal. One bash file, no daemon, nothing resident.

```console
$ dcc dash

  DOCKER  ·  default  ·  engine 29.6.2  ·  8 CPU  ·  overlayfs  ·  host RAM 412 MB
────────────────────────────────────────────────────────────────────────────────
  2 stacks · 4/6 containers up · CPU 6.3% of host · 21.4 GB on disk

  IDENTIFIED WASTE (counted from the API, not estimated by docker)
    build cache           4.2 GB  12 entries, 0 in use        dcc clean-build
    stopped layer         912 MB  2 containers                dcc clean
    unused images         1.0 GB  node:18, postgres:15        dcc clean
    orphan volumes         30 MB  2 unmounted                 dcc volumes-orphan
                          6.1 GB  verified

  ⚠  1 killed the hard way (137)  SIGKILL / OOM / stop with timeout
  ⚠  stopped weeks ago            otro

STACKS — grouped by compose project

 ◐ demo                        2/3 up
   ▸ web                  up 2h            12.4% ✓ 8080→80      nginx:alpine
   ▸ db                   up 2h             0.8%   -            postgres:16
   ▹ worker               exit 137 20m         —   -            python:3.12

 ● (loose)                     1/1 up
   ▸ suelto-1             up 11m            0.0%   -            busybox

 ◐ otro                        1/2 up
   ▸ api                  up 5d            31.6% ✓ 3000→3000    node:20
   ▹ cache                exit 0 3w            —   -            redis:7
────────────────────────────────────────────────────────────────────────────────
```

Colours are stripped above. On a terminal, severity is colour-coded: grey for a
clean exit, yellow for a kill, red for a real error. Sizes are counted from the
raw API, never estimated — Docker's `Reclaimable` does not add up under the
containerd snapshotter.

Type a name wrong and it finds what you meant:

```console
$ dcc dex demo_wb-1
No running container is called 'demo_wb-1'.

  CLOSEST MATCH

    ● demo_web-1  web
      stack: demo
```

For **native Docker Engine on Linux**. If you run Docker Desktop you already
have this UI.

## Install

```bash
curl -LO https://github.com/velezanthony/docker-control-center/releases/latest/download/docker-control-center.sh
chmod +x docker-control-center.sh
mv docker-control-center.sh ~/.local/bin/dcc
dcc
```

~80 KB, no dependencies beyond `docker`, `bash` and `awk`. The name you give the
file is the name it answers to — rename freely.

<details>
<summary><b><code>dcc: command not found</code> on Debian or Ubuntu?</b></summary>

`~/.profile` adds `~/.local/bin` to your PATH, but only **if the directory
already existed when you logged in**. Create it during install and that check
already ran hours ago.

```bash
case ":$PATH:" in *":$HOME/.local/bin:"*) echo "on PATH" ;; *) echo "missing" ;; esac

echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc   # bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc    # zsh
fish_add_path ~/.local/bin                                 # fish
```

Fedora and RHEL add it via `/etc/profile.d/`. On Arch and Alpine you add it
yourself.
</details>

From source:

```bash
git clone https://github.com/velezanthony/docker-control-center
cd docker-control-center && make link
```

`make link` symlinks the build, so `make bundle` is enough to update `dcc`.

## Language

English and Spanish, picked from your `$LANG`. Change it with `dcc lang es`;
it is stored in `~/.config/dcc/config` and applies to every command.

## Requirements

`docker`, `bash` 4+, `awk` (any — GNU extensions are avoided on purpose) and the
usual POSIX utilities. Optional, and it degrades gracefully without them:

| Missing | What you lose |
|---|---|
| `curl` | Sizes: no disk, no waste report |
| `jq` | The same, plus `inspect` and `volume-inspect` |
| `tput` | Width detection; assumes 100 columns |
| `systemd` | Only `dcc engine` |

Any Linux distro. Not macOS (bash 3.2, no native engine), not Windows.

## Backups

`dcc volume-backup` writes to a `backups/` directory **next to the tool**, not
next to your shell. Point it elsewhere with `BACKUP_DIR=/safe/path`.

## Docs

Full documentation: **<https://velezanthony.github.io/docker-control-center/>**

Hacking on it: [CONTRIBUTING.md](CONTRIBUTING.md) ·
Vulnerabilities: [SECURITY.md](SECURITY.md) ·
[MIT](LICENSE)

[![Sponsor](https://img.shields.io/github/sponsors/velezanthony?logo=githubsponsors&color=EA4AAA)](https://github.com/sponsors/velezanthony)
