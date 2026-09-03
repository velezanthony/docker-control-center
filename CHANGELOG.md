# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Nothing has been released yet.** The repository carries no tags.
> `DCC_VERSION` says `0.9.0`, which is the version the code announces — not a
> version anyone has been able to download. The first published version will be
> the first entry with a date.

## [Unreleased]

### Fixed

- **The release asset is published as `dcc`.** A GitHub release names the asset
  after the basename of the uploaded file, so it went out as
  `docker-control-center.sh` while the README, both landing pages and both
  installation pages sent people to `.../download/dcc`. Five 404s waiting for the
  first tag — the release notes the workflow writes made a sixth. A test now
  checks the workflow and the docs agree, in both directions.
- **`dcc sh <name>` in a pipe.** It ran `docker exec -it` with the flag fixed, so
  `dcc sh api </dev/null` died with *"the input device is not a TTY"*. `dex` had
  the check already; both now share one `dcc_exec`.
- **A stack operation that Docker refuses says so.** `stack-start`, `stack-stop`,
  `stack-restart` and `stack-rm` printed the ✓ or nothing at all: a failing
  daemon left `stack-start api && ./deploy.sh` deploying against a stack that had
  not started.
- **The panel no longer suggests commands that do not exist.** The footer read
  `dcc help · make clean · make clean-build`, sending whoever downloaded a lone
  `.sh` to a Makefile they do not have. The docs likewise promised `make dash`,
  `make logs`, `make volume-backup-all` and the `C=` / `S=` variables — none of
  which exist. The prefix now comes from `$DCC_CMD`, and a test rejects any
  hardcoded `make <command>` that is not a real target.
- **The help no longer promises commands the dispatcher rejects.** The `name: ##`
  format of `src/commands.txt` was parsed by four different rules — in
  `common.sh`, in `help.sh`, in `build.sh` and in its own test — and they already
  disagreed: a target such as `Foo_bar` was rendered by the help and embedded in
  the bundle, then refused as unknown. One parser now, `dcc_parse_commands()`.
- **`dashboard --only` rejects what it does not understand** instead of silently
  painting the whole panel, and a bare `--only` no longer dies with `set -u`'s
  *"unbound variable"*.
- **Exit code `3`** (cancelled by the person running it) is documented; the page
  listed only `0`, `1` and `2`. It is documented for what it is: `3` comes from
  the pick menu only. Saying no to a written confirmation — `clean-hard`,
  `stack-rm` — still exits `0`, one of the traps
  [Limitations](https://velezanthony.github.io/docker-control-center/users/limitations/)
  covers.

### Changed

- **The single file's dispatcher lives in `src/scripts/bundle-main.sh`.** It used
  to sit inside a quoted heredoc in `build.sh`, where shellcheck does not look:
  the product's entry point went unlinted and unformatted. It is always
  concatenated last, and its guard is the inverse of every other module's.
- **`make fmt` is gone.** Measured: `shfmt` disagreed with all nine scripts —
  1333 lines of diff on a tree nobody had touched — because it cannot leave
  `f() { g; return; }` alone. `shellcheck` is the style authority; there is no
  formatter. The shfmt editor extension moved to `unwantedRecommendations`.
- **`make check` also parses `build.sh` and `deps.sh`**, the packager and the
  dependency fetcher.

### Added

- **A [Limitations](https://velezanthony.github.io/docker-control-center/users/limitations/)
  page**, in both languages, holding thirty things the tool does not do, does
  badly, or does quietly — each one reproduced against the built single file
  before it was written down. The ones worth knowing before you rely on it:
  `volume-restore` refuses to restore a volume you deleted, which is the disaster
  a backup exists for; backups are taken hot and silently overwrite the previous
  one; five of the seven destructive commands never ask; a written confirmation
  auto-denies and exits `0` when there is no terminal; and `ram` reports
  `0.0 MB` rather than an error whenever the daemon is not in the local `/proc`.
  Every other document now links here instead of keeping its own partial copy.
- **`gzip` and `mktemp` declared as the hard dependencies they are.** Neither was
  listed anywhere, and both fail misleadingly: without `gzip`, `volume-restore`
  accuses your backup of being corrupt.
- **The documentation site is genuinely bilingual.** `commands`, `language` and
  the whole `engineering` guide were only in English and the language selector
  served them silently through the fallback. Structural parity between each page
  and its translation is verified.
- **Guards for the whole class of drift found above**: the two catalogues must
  carry exactly the same keys (a missing one showed the raw key name on screen —
  there is no English fallback at runtime); nothing may hardcode a `make` that is
  not a target; the download URL must name the published asset; the dispatcher
  must be the last thing in the bundle.
- Test coverage for `render_volumes`, which had none, and for `severity_cell`'s
  branch for a `Created` container.

### Removed

- Seven dead message keys, three of them duplicated. Both catalogues now hold the
  same 205 — counted by loading the catalogue and reading `${#MSG[@]}`. A naive
  `grep` for `[key]=` answers 188, because it misses every key with a hyphen
  (`help_dash-fast`, `help_stack-start`…). The number that matters is not the
  count anyway: it is the test comparing the two catalogues both ways.

---

## [0.9.0] — unreleased

The initial body of work: the dashboard, the operations, the single-file bundle,
the two message catalogues, the ShellSpec suite and the CI that runs it in three
configurations: bash 5.2 + mawk, bash 4.4 + mawk 1.3.3, and that same bash 5.2
with gawk as the system awk. Two bash versions, not three — the `gawk` job runs
on the same `ubuntu-latest` as `check` and only swaps the awk.

It carries no tag and was never published.
