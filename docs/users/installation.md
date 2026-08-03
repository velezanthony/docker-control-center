# Installation

## One file

```bash
curl -LO https://github.com/velezanthony/docker-control-center/releases/latest/download/dcc
chmod +x dcc && mv dcc ~/.local/bin/
dcc dash
```

A ~100 KB executable. Nothing to install and no dependencies beyond `docker`,
`bash` and `awk`. It carries both languages and everything else inside.

## Cloning the repository

If you want to touch the code or build the single file yourself:

```bash
git clone https://github.com/velezanthony/docker-control-center
cd docker-control-center
make
```

`make` with no arguments prints the full command list.

!!! note "The helper image"
    The first time you use `volume-tree`, `volume-backup` or `volume-restore`,
    Docker will pull the `alpine` image (about 8 MB). It is what runs inside the
    volume. You can change it with `HELPER_IMAGE=busybox`.

## Requirements

**Required**, and that is all:

- **Native Docker Engine**, with the socket readable by your user
- **bash 4 or newer** (associative arrays)
- **awk** — any. The code deliberately avoids GNU extensions, so it works the
  same with `mawk` (Debian, Ubuntu) as with `gawk` (Fedora, Arch)
- The usual **POSIX utilities**: `sed`, `grep`, `sort`, `tr`, `cut`, `paste`,
  `wc`, `du`, `xargs`. They ship with any Linux; they are listed for honesty,
  not because you need to install them

**Recommended.** If one is missing the tool does not break: it warns and keeps
working with less information.

| Missing | What you lose |
|---|---|
| `curl` | Sizes. The dashboard falls back to fast mode and shows no disk or junk |
| `jq` | The same, **and** `inspect` and `volume-inspect` stop working |
| `tput` | Terminal width detection; assumes 100 columns |
| `systemd` | Only the `engine` command |

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
| **Alpine** | Untested. You would need to install `bash`, and `engine` will not work without systemd |
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
  bash    5.2.21
  docker  /usr/bin/docker
  jq      not installed
  language  en (locale)
  config  /home/you/.config/dcc/config
```

That is the first thing to look at when something behaves oddly, and the first
thing you will be asked for if you open an issue.
