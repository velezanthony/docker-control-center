# Docker Control Center

[![CI](https://github.com/velezanthony/docker-control-center/actions/workflows/ci.yml/badge.svg)](https://github.com/velezanthony/docker-control-center/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A Docker dashboard for the terminal. One bash file, no daemon, nothing resident.

📚 **Docs:** <https://velezanthony.github.io/docker-control-center/> ·
**[Limitations](https://velezanthony.github.io/docker-control-center/users/limitations/)**

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

**Nothing has been released yet** — the repository carries no tags, so there is
nothing at `releases/latest` to download. Until the first one, build it:

```bash
git clone https://github.com/velezanthony/docker-control-center
cd docker-control-center && make link
```

`make link` symlinks the build into `~/.local/bin`, so `make bundle` is enough
to update `dcc`.

<details>
<summary><b>From the first release on</b></summary>

```bash
curl -LO https://github.com/velezanthony/docker-control-center/releases/latest/download/dcc
chmod +x dcc && mv dcc ~/.local/bin/
dcc
```

Under 90 KB, and beyond `docker`, `bash` 4+ and `awk` it needs only the usual
POSIX utilities. Not quite zero, though: `volume-tree`, `volume-backup`,
`volume-backup-all` and `volume-restore` pull the `alpine` image from Docker
Hub to work inside the volume — pick another with `HELPER_IMAGE=busybox`. The
name you give the file is the name it answers to — rename freely.
</details>

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

## Language

English and Spanish, picked from your `$LANG`. Change it with `dcc lang es`;
it is stored in `~/.config/dcc/config` and applies to every command.

## Requirements

`docker`, `bash` 4+, `awk` (any — GNU extensions are avoided on purpose) and the
usual POSIX utilities. These are optional — but only the first three degrade
gracefully:

| Missing | What you lose |
|---|---|
| `curl` | Sizes: no disk, no waste report |
| `jq` | The same, plus `inspect` and `volume-inspect` |
| `tput` | Width detection; assumes 100 columns |
| `systemctl` | Not graceful: `dcc engine` asks systemd, not Docker, so it announces `dockerd stopped` and tells you to run `sudo systemctl start docker` with the daemon running fine |

Any Linux distro. Not macOS (bash 3.2, no native engine), not Windows.

The full list of what it does not do, does badly, or does quietly:
**[Limitations](https://velezanthony.github.io/docker-control-center/users/limitations/)**.

## Backups

`dcc volume-backup` writes to a `backups/` directory **beside the directory the
tool lives in**, not next to your shell: installed at `~/.local/bin/dcc`,
backups land in `~/.local/backups`. Point it elsewhere with
`BACKUP_DIR=/safe/path`.

The destination is always `<name>.tar.gz`, so every run overwrites that volume's
previous backup without asking, and the tar is taken hot, with the containers
running. Read [Limitations](https://velezanthony.github.io/docker-control-center/users/limitations/)
before you rely on one.

## Docs

Hacking on it: [CONTRIBUTING.md](CONTRIBUTING.md) ·
Vulnerabilities: [SECURITY.md](SECURITY.md) ·
Everything else: <https://velezanthony.github.io/docker-control-center/>

## Support

[![Sponsor](https://img.shields.io/github/sponsors/velezanthony?logo=githubsponsors&color=EA4AAA)](https://github.com/sponsors/velezanthony)

If this saves you the Docker Desktop licence, consider
[sponsoring its development](https://github.com/sponsors/velezanthony). It helps
keep it maintained.

## License

MIT — see [LICENSE](LICENSE).
