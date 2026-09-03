# Limitations

This page lists what the tool does **not** do, does badly, or does quietly when
it should complain. Everything here was checked against the code on this branch.
It is not a wishlist or a roadmap: it is what you get if you install it today.
Read [Commands](commands.md) for what each command does; this page is about
where each one stops.

## Where it runs

The target is **Linux with a native Docker Engine**, talking to a `unix://`
socket your user can read. That is the only configuration where every feature
works.

| | |
|---|---|
| **Linux, native engine** | Everything works |
| **Docker Desktop, colima, WSL2 with the engine in a VM** | Panel and commands work; `ram` and `engine` are wrong (below) |
| **Rootless Docker** | Works, but the CPU column falls back to `docker stats` and `engine` reports the wrong state |
| **Remote contexts** (`ssh://`, `tcp://`, remote `DOCKER_HOST`) | Every size disappears (below) |
| **macOS, Windows** | No. macOS ships bash 3.2 and the code needs bash 4 associative arrays |
| **Podman** | Not supported. Nothing in the code accounts for it and it has never been tried |

### The engine's RAM is read from the local `/proc`

`ram`, and the `host RAM` figure in the panel header, walk `/proc` looking for
`dockerd`, `containerd` and `docker-proxy`. If the daemon does not live in the
same `/proc` — Docker Desktop, colima, WSL2 with the engine in its own VM, or
any remote context — the loop matches nothing, the total stays at zero, and you
get `0.0 MB TOTAL` with exit code `0`. That is indistinguishable from an engine
that uses no memory. There is no warning.

On a remote context it is worse than zero: the number you see is the RAM of the
**local** `dockerd`, printed under the header of the remote engine.

### `engine` asks systemd, not Docker

`engine` runs `systemctl is-active docker`. When `systemctl` is missing or the
daemon is not managed by the system systemd — Docker Desktop, WSL2, Alpine with
OpenRC, rootless Docker, inside a container — the check fails and the command
prints `dockerd stopped` and tells you to run `sudo systemctl start docker`,
while the daemon is running perfectly well. Verified on this machine with a live
daemon and `systemctl` removed from `PATH`.

### Remote contexts lose every size

The panel reads sizes from the Docker API over the socket. The code strips a
`unix://` prefix and then requires the result to be a socket file. `ssh://host`
and `tcp://host:2376` are not, so it drops into fast mode and every section that
needs a size prints `No size data`. `status` — whose whole job is counted junk
plus real disk usage — becomes two lines of `No size data`.

The warning you get is `without socket/curl/jq there are no sizes`. On a remote
context all three are present and none of them is the problem. The Docker CLI
could answer with `docker system df`; there is no fallback to it.

### The CPU column needs cgroup v2 at a known path

Per-container CPU is read straight from
`system.slice/docker-<id>.scope/cpu.stat` or `docker/<id>/cpu.stat`. On cgroup
v1, and on rootless Docker — whose scopes hang off `user.slice/user@UID.service`
— neither path exists and the panel falls back to `docker stats --no-stream`.
Nothing breaks; `ps` just takes noticeably longer — roughly twice as long in the
measurements taken here, though the absolute times depend entirely on your
machine and what else it is doing.

## What it needs

### Required

Without these, commands fail:

| | Used by |
|---|---|
| `docker` CLI and a reachable daemon | Everything |
| **bash 4 or newer** | Everything — associative arrays |
| `awk` | Everything. No GNU extensions, so `mawk` and `gawk` behave the same |
| `sed`, `grep`, `sort`, `tr`, `cut`, `paste`, `wc`, `du`, `xargs` | Various |
| **`mktemp`** | The panel, `volume-backup`, `lang` |
| **`gzip`** | `volume-restore` |

`mktemp` and `gzip` are hard dependencies and are **not listed** in
[Installation](installation.md). They ship with every mainstream Linux, so this
matters mostly when you run the tool inside a minimal container.

!!! danger "The error message can blame the wrong thing"
    Without `gzip`, `volume-restore` prints *"…tar.gz is corrupt (bad gzip).
    NOTHING has been deleted."* It accuses your backup. The backup is fine; the
    tool is missing. Someone could delete a healthy tarball over this.

    Without `mktemp`, the panel prints raw interpreter errors about a path you
    never chose (`/stats.txt: Permission denied`), renders half a panel, and
    exits `0`.

### Optional

If one of these is missing the tool keeps working with less information:

| Missing | What breaks | How you find out |
|---|---|---|
| `curl` | All sizes: disk, junk, volume and image sizes | Yellow warning, then `No size data` |
| `jq` | The same, **and** `inspect` and `volume-inspect` | Same warning; `inspect` says it needs `jq` |
| `tput` | Terminal width detection; 100 columns assumed | Nothing. Silent |
| `systemctl` | `engine` reports the wrong state | Nothing. It states the wrong answer confidently |
| `getconf` | Page size is assumed to be 4096 | Nothing. On 16 KB or 64 KB page kernels every RAM figure is off by that factor |

Two rough edges around this:

- For `inspect`, the `jq` check runs **after** the picker. You choose a
  container from the menu and only then are told `jq` is missing.
- The message says `sudo apt install jq`. On Fedora, RHEL, Arch, openSUSE or
  Alpine that command does not exist.

### `dcc version` does not cover the confusing cases

`dcc version` reports `docker`, `jq`, `curl`, `awk` and `tput`. It says nothing
about `gzip`, `mktemp`, `getconf` or `systemctl` — which are exactly the four
whose absence produces the most misleading failures above.

## Commands that destroy things

Seven commands delete or stop things. **Two of them ask for confirmation.** The
other five act immediately.

| Command | What it destroys | Asks? |
|---|---|---|
| `stack-rm` | The stack's containers (`docker rm -f`) | **Yes** |
| `clean-hard` | `docker system prune -af` | **Yes** |
| `clean` | Every stopped container on the machine, dangling images, unused networks | No |
| `clean-build` | The whole build cache (`builder prune -af`) | No |
| `rm-image` | An image (`docker rmi`) | No |
| `volume-restore` | The current contents of a volume | No |
| `kill-all` | Stops every running container | No |

Two things worth knowing about that table:

- **`clean` is described as "safe".** That means it does not touch volumes. It
  still deletes every stopped container on the machine, with its writable
  layer, irreversibly, without asking.
- **`kill-all` does not kill.** It runs `docker stop`: SIGTERM with a ten-second
  grace period, not SIGKILL. A container that ignores SIGTERM costs ten seconds
  each.

When a command does ask, it wants the word **exactly** as printed — `YES` in
English, `SI` in Spanish, uppercase, no accent. `yes`, `si` or `y` all count as
"no".

Saying no exits `0`, not `3`. [Commands](commands.md#exit-codes) covers what the
exit codes mean and where that one bites.

## Backups: read this before you trust them

This is the part of the tool most likely to hurt you, so it gets the most space.

### They are taken hot

`volume-backup` and `volume-backup-all` run `tar czf` over the volume while
everything keeps running. No container is stopped. Nothing checks whether the
volume is even in use. A tar of a live Postgres or MySQL data directory can come
out inconsistent and fail to restore — and the green ✓ you get looks exactly
like the one from a good backup.

If the data matters, stop the containers yourself first.

### They overwrite the previous one, silently

The destination is always `<backup dir>/<volume name>.tar.gz`. There is no
versioning, no timestamp, and no prompt. **Every run destroys the previous
restore point.** A backup taken over a broken volume replaces the good one from
last week.

### Where they land is probably not where you expect

The backup directory is the **parent** of the directory the tool lives in — not
your current directory. Installed at `~/.local/bin/dcc`, backups go to
`~/.local/backups`. Installed to a system path such as `/usr/local/bin`, the
tool tries `/usr/local/backups`, which normally needs root: the command exits
with `2`, the code the table calls a usage error, for what is really a
permissions problem.

Set the location yourself:

```bash
BACKUP_DIR=/safe/path dcc volume-backup-all
```

The tarballs themselves are created readable only by you (`0600`). The directory
is created with your umask, so on a default setup other local users can list the
**names** of your volumes, though not read the contents.

Interrupting a backup with Ctrl-C leaves a `.backup.XXXXXX` temporary file
behind. There is no cleanup handler on it.

### `volume-restore` cannot restore a volume you deleted

This is the important one. `volume-restore` validates the name you give it
against `docker volume ls -q`. If the volume is gone — the exact disaster a
backup exists for — it answers `There is no volume called 'X'` and exits `1`,
with the intact tarball sitting right there in the backup directory.

The workaround is one command:

```bash
docker volume create myvol && dcc volume-restore myvol
```

### `volume-restore` asks nothing

It is the most destructive command in the tool — it runs `rm -rf` over the
volume's contents from inside a container — and it has **no confirmation of any
kind**. It also does not check whether the volume is mounted: Docker will
happily mount it a second time, and you will delete the data underneath a
running process.

### It checks the wrapper, not the tar

The check before deleting is `gzip -t`. That validates the **gzip envelope**,
not that the archive inside is complete or that the extraction will finish. The
two-phase design does protect you from a truncated download; it does not
guarantee the tar is sound.

### It needs twice the volume's free space

Restore extracts into `/data/.dcc-restore` inside the volume, then deletes the
old contents, then copies. On a full volume or one with a quota, it fails. You
get no warning about the space requirement beforehand.

If it is interrupted between the two halves, a `.dcc-restore` directory is left
inside your volume and the volume is half-written. The backup is untouched.

### The helper container

`volume-tree`, `volume-backup`, `volume-backup-all` and `volume-restore` run a
helper container over your volume — `volume-backup-all` runs one per volume, all
through the same `backup_one`. It is `alpine`, an **unpinned floating tag**, pulled from Docker
Hub the first time. For restore the volume is mounted **read-write**, the
container runs as root, and it gets the default bridge network — no
`--network none`.

The `HELPER_IMAGE` variable chooses which image gets handed your volumes. It is
documented as a convenience; it is also the thing to be careful with, because
`HELPER_IMAGE=someone/else dcc volume-backup-all` would send every volume on the
machine through an image you did not pick.

## When it stays quiet instead of failing

### Written confirmations auto-deny without a terminal

`confirm()` reads from stdin without checking that there is a terminal. In a
script, a cron job or CI, the read fails, the answer is empty, it does not match
the required word, and the command **returns `0` having done nothing** — with no
"cancelled" message.

```bash
dcc clean-hard && echo "disk freed"    # prints "disk freed". Nothing was freed.
```

Verified: with stdin closed, `clean-hard` prints its red warning, issues no
Docker call at all, and exits `0`. The picker does check for a terminal;
`confirm()` does not.

### `0 MB` of RAM and `No size data`

Both covered above. Both return `0`. Neither is distinguishable from a real
answer:

- `ram` prints `0.0 MB TOTAL` when it cannot read the daemon's `/proc`.
- `No size data` appears wherever a size is missing, whatever the cause —
  missing `curl`, missing `jq`, or a remote context.

### With the daemon down, some commands report a state they could not read

`logs`, `stop`, `sh`, `inspect`, `start`, `restart`, `rm-image` and the
`volume-*` commands all go through the picker, which does not check whether the
Docker call succeeded. With the daemon unreachable you get Docker's raw error
leaking to the screen, followed by `No containers available.` — or the volume or
image equivalent — which is a claim about a state that was never read. Exit code
`1`.

`stacks`, `networks`, `ctx`, `stats` and `volumes-orphan` give you only Docker's
raw error and nothing of the tool's own.

`kill-all` and `dash` do this correctly and say the daemon is not responding.
Note that `dash` prints the misleading sizes warning **before** the real error.

### Extra arguments are ignored

The panel views do not receive their arguments. `dcc ps whatever`,
`dcc status whatever` and `dcc version whatever` all render the normal output
and exit `0`, rather than telling you the argument means nothing.

### Two commands exist that the help never mentions

`dcc dashboard` runs the panel through its internal `--only` interface, whose
value is not validated: `dcc dashboard --only=nope` paints an empty panel and
exits `0`. `dcc bundle` calls itself with no arguments and prints the help. This
is a consequence of how the single file dispatches; neither is in the command
list.

### The list you get after a typo is incomplete, and in Spanish

Mistype a command and you get a usage line plus a list of **29** of the 40
commands. The list is built from the operations that have an implementing
function, so the views and the built-ins are missing: `dash`, `dash-fast`,
`status`, `ps`, `psa`, `images`, `volumes`, `dex`, `lang`, `help` and `version`
are not in it — including the flagship command and `help` itself.

The usage line above it is hardcoded in Spanish. `DCC_LANG=en dcc frobnicate`
prints `dcc <operación> [preselección]`.

### `stop` on a stopped container says it does not exist

`stop` and `sh` look in the list of **running** containers. Given a container
that exists but is stopped, they answer `There is no running container called
'X'` and exit `1`. The message is false, and it means `stop` is not idempotent:
the second call fails as if you had made a typo.

### With `$HOME` unset it aborts before it starts

In a cron job without `HOME`, a systemd unit, `env -i` or a minimal CI
container, the tool dies on a raw interpreter error — `HOME: unbound variable` —
with exit `1`, before printing a single word of its own. Setting either `HOME`
or `XDG_CONFIG_HOME` avoids it.

## Output and terminal

- **No `NO_COLOR` support and no pipe detection.** The colour escapes are plain
  constants, emitted unconditionally. Redirect to a file or pipe into another
  command and the ANSI escapes go with it. `NO_COLOR=1 TERM=dumb` changes
  nothing. There is no flag to turn colour off.
- **Columns drift outside UTF-8.** Padding counts characters, and in a non-UTF-8
  locale such as `LC_ALL=C` that count is bytes: every accented character eats
  one pad space. `pad "café" 8` emits four trailing spaces under UTF-8 and three
  under `C`. The Spanish interface — *Volúmenes*, *Caché*, *Imágenes* — drifts
  visibly. The box-drawing characters (`─ ● ▸ ⌀ ★ ✓`) need a UTF-8 terminal too.
- **Width is clamped.** It comes from `tput cols`, or 100 if `tput` is missing,
  and is then clamped to between 60 and 110 columns. A 200-column terminal gets
  110; a 40-column one gets 60 and wraps.

## Not released yet

**The repository carries zero tags. Nothing has ever been published.** The
`releases/latest` download URL has nothing to serve.

The only install path that works today is cloning and running `make link`, as
[Installation](installation.md) describes. Consequences:

- **The symlink is absolute** and points into the clone's `dist/`. Move the
  clone, rename it, or delete it, and `dcc` becomes a dangling link that dies
  with *"No such file or directory"*. You are tied to leaving the clone where it
  is.
- **Nothing to verify a download against.** When releases do start, the workflow
  publishes the executable and nothing else — no sha256, no signature, no
  attestation. The install recipe is `curl` an executable and run it.
- **The publishing path has never run.** The release workflow only triggers on a
  tag, and there has never been one. The first tag will be its first execution.
- **There is no uninstaller.** No `make uninstall`, no `dcc uninstall`. Removing
  it means deleting by hand: `~/.local/bin/dcc`, `~/.config/dcc/config`, your
  backup tarballs, and — in the clone — `vendor/`, `dist/`, `coverage/` and the
  `.git/hooks/pre-commit` that `make hooks` installs.

## Language

The interface is **English and Spanish**, and only those two. See
[Language](language.md) for how it is chosen.

**An unrecognised value falls back to English without a word.** `DCC_LANG=fr`
gives you English, and `dcc version` then reports `language en (env)`: the
source is right, but the value you set is never echoed back and no warning says
it was discarded.

Some text is in English whatever you choose:

- Command names.
- Anything Docker prints straight through: `ctx`, `stats`, `logs`, `tail`,
  `rm-image`, `volume-tree`, and the `docker system df` that follows the clean
  commands.
- The column headers of `stats`, because it asks Docker for a formatted table
  and Docker writes those headers itself. `networks` deliberately avoids this,
  so the two commands are inconsistent with each other.

And some text is in Spanish whatever you choose: the usage line after a typo,
and four internal error messages that never go through the catalogue.

On this site, *How to contribute*, *Changelog* and *Security* exist only in
English. The navigation label is translated; the page you land on is not.
