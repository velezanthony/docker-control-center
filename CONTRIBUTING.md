# Contributing

```bash
make check     # lint + parse + tests. All green or no commit. No Docker needed.
make dev dash  # rebuild the single file and run it — the everyday loop
```

## The map

```
src/
  scripts/            common · ops · dashboard · dex · help · lang
                      engine-ram · container-cpu · metrics.jq · bytes.jq
                      bundle-main — the single file's dispatcher
  tests/              ShellSpec specs + spec_helper.sh + fixtures.sh
  i18n/en.sh es.sh    message catalogues
  commands.txt        which commands the product has, in what order and section

Makefile              development toolchain. Builds, tests and lints the
                      product; run, dev and lang launch it, implement nothing
build.sh              concatenates src/scripts/ into dist/
deps.sh               fetches vendor/ from dependencies.txt, verifying sha256
```

Three rules explain most of the design:

1. **`dashboard.sh` is the only source of presentation.** `ps`, `volumes`,
   `images` and `status` are views of it via `--only`.
2. **`ops.sh` is the only source of operations.** In the Makefile there is no
   shellcheck and nothing to test.
3. **The Makefile implements nothing.** It builds, tests and lints — and `run`,
   `dev` and `lang` do launch the product, which is why `make dev dash` above is
   the everyday loop.

## Adding things

| You add | You touch | How it works |
|---|---|---|
| A script | **nothing**, to dispatch it | `build.sh` discovers the directory; `foo_main()` becomes `dcc foo`. Only touch `BUNDLE_ORDER` to decide **where** it is concatenated. The help is a separate list, rendered from `src/commands.txt`: a module that is not in there works and is never advertised — that is how `dcc dashboard` and `dcc bundle` came to exist with no help entry |
| An operation | `op_x()` + a line in `src/commands.txt` | dispatch is the **intersection** of the two: `commands.txt` says what exists, `op_x()` implements it. Miss either and the command is invisible. Two tests demand the line **and** its `help_x` catalogue key |
| A language | `src/i18n/xx.sh` **and a branch in the `case` of `dcc_load_language()`**, in `common.sh` | the catalogue is found by glob, but resolution maps `es*` → `es` and **everything else** → `en`. Drop in `fr.sh` alone and `dcc lang fr` answers *"✓ Language set to Français"*, writes `DCC_LANG=fr` to the config and keeps painting English, without a word. The header of `src/i18n/en.sh` already says this. A missing key falls back to the key name at runtime, but a test compares the catalogues both ways: an incomplete one fails `make check` |
| On-screen text | a catalogue key, via `t`/`tf` | never a literal. The **whole sentence** goes in the catalogue: "Choose a %s" produced *"Elige un imagen"* |
| A test | `src/tests/x_spec.sh` | copy the header of an existing spec: the DSL trips seven inherent shellcheck false positives and `make lint` fails without it. It disables both SC2317 and SC2329 — the same check under its old and new name, so it lints clean on 0.9.0 (what Ubuntu ships to CI) and on 0.11.0 |
| Test data | `src/tests/fixtures.sh` | invented, never from your `docker ps` |

Every script with a `*_main()` entry point ends with the guard. Write it
however you like — one line or three, `if` or `&&`. The bundle sets
`DCC_BUNDLE`, so the first test is false there and `build.sh` never has to
recognise, let alone edit, the line. Two files are outside the rule:
`bundle-main.sh`, whose guard is the inverse, and `common.sh`, which is library
only and has none.

```bash
if [ -z "${DCC_BUNDLE:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	foo_main "$@"
fi
```

Loading a sibling module goes on ONE line, guard included, so the bundle — where
everything is already defined — never fires it:

```bash
# shellcheck source=src/scripts/engine-ram.sh
declare -F engine_ram >/dev/null 2>&1 || . "$DCC_DIR/engine-ram.sh"
```

## The suite is hermetic

No test may touch the Docker of the machine running it. That takes **two**
mechanisms, because they cover different things:

| Test shape | Lock |
|---|---|
| `Include`s a script and calls its functions | `spec_helper.sh` defines a `docker()` that fails with 127, so forgetting a stub is an error and not a green run against someone's containers |
| Runs the bundle as a **process** (`bundle_spec.sh`) | a fake `docker` at the front of `PATH` — a bash function does not cross into a child, so the lock above cannot reach there |

The second one was missing, and those examples talked to the real daemon: they
gave one answer on a laptop with containers, another on `ubuntu-latest` with
none, and a third inside the `bash4` container with no docker client at all.
That is where a `stacks` returning 2 came from, once, never to be reproduced.

Verified — same numbers with a fake `docker`, with none on the `PATH`, and with
a broken `DOCKER_HOST`.

Catalogues are **data, not code**: they are `source`d, so a backtick or a `$( )`
would execute. A test forbids both.

## Comments

Minimum. They explain the code; they are not a changelog — that is what commit
messages are for. One or two lines, never a paragraph. Keep the constraint
(`# mawk aborts when it cannot open a file`), drop the anecdote (`# failed 1 in
10`). Needing to explain a lot means the function is too big.

More comments than code is a bug. Measure against lines of **code**, not the
file total.

## Conventions that look odd and are not

| What | Why |
|---|---|
| `pad()` instead of `printf "%-Ns"` | printf counts BYTES; accents break the table |
| `SEP` (0x1f) instead of tab for `read` | bash collapses whitespace IFS; one empty field shifts every later one |
| No `set -e` anywhere | `pick`, `confirm` and `grep` return != 0 as a legitimate answer |
| Scripts only run when launched directly | the `DCC_BUNDLE` guard is what makes them testable **and** packageable |
| `make lint` leaves 2 cores free | it runs on a machine where someone is working |
| Docker's `.Reclaimable` is never used | it does not add up under containerd |
| CPU does not come from `docker stats` | that waits ~1 s between samples; cgroups take 500 ms |
| `declare -A x=()` and not `declare -A x` | without `=()` it is declared but unset and `${#x[@]}` blows up under `set -u` |
| `join_list` instead of `paste -sd', '` | `-d` takes a LIST that ROTATES: three items gave `a,b c` |
| No bash 5 without a fallback | the README promises bash 4+ |
| No `rg`, `sd` or `fd` | they ship with no distribution — a test watches for them |
| The `name: ## text` format is parsed by `dcc_parse_commands()` **only** | there used to be four rules — here, in `help.sh`, in `build.sh` and in its own test. A target named `Foo_bar` was rendered by the help and embedded in the bundle, and rejected by dispatch as unknown |
| Screen text never hardcodes `make` | the prefix comes from `$DCC_CMD`. The footer read `dcc help · make clean`, sending whoever downloaded a lone `.sh` to a Makefile they do not have. A test watches for it |

## The single file

`make bundle` produces `dist/docker-control-center.sh`: a **concatenation**, not
a self-extractor. The header sets `DCC_BUNDLE`, which makes every guard false,
so the scripts only DEFINE when pasted together. Nothing is stripped:
`strip_comments()` drops the shebang on line 1 and the `# shellcheck source=`
directives, and nothing else. Every comment ships — 321 of the 2052 lines of the
86 KB (88 365 bytes) the user downloads are comments, in Spanish.

`build.sh` runs under `set -uo pipefail` **without `-e`**, and the `mv` that
publishes the result is unconditional. `resolve_modules()` does abort on a
missing module, but the catalogues, the `.jq` files and `src/commands.txt` go in
through command substitution: their failure prints its own error, writes the
bundle anyway and exits `0`. Delete `src/commands.txt` and you get a bundle that
starts, dispatches, and lists no command at all, with `DCC_HELP_SRC=''` inside.
`bundle_spec.sh` would not notice — it only asserts that the string
`DCC_HELP_SRC=` is present. Read what a build printed; do not trust its exit
code.

The dispatcher is `src/scripts/bundle-main.sh` and it is **always concatenated
last**, so everything it calls is already defined. It is the one file kept out of
the automatic discovery, and its guard is the inverse of every other module's —
it only runs with `DCC_BUNDLE` set. It used to live inside a quoted heredoc in
`build.sh`, where shellcheck does not look: the product's entry point went
unlinted and unformatted. Verified by injecting an SC2086 in there — shellcheck
came back clean.

| In the repository | In the bundle |
|---|---|
| `src/i18n/*.sh` | `_catalog_en` / `_catalog_es` functions |
| `*.jq` | `JQ_BYTES` / `JQ_METRICS` variables |
| `src/commands.txt` | the `DCC_HELP_SRC` variable |
| the invoking name | whatever you renamed the file to, via `$DCC_CMD` |

## Exit codes

| | |
|---|---|
| `0` | done, **or** already in that state |
| `1` | what you named does not exist, or the operation did not go through |
| `2` | usage error, or a missing value with no terminal to ask on |
| `3` | cancelled by whoever ran it, **from a pick menu** |

A typo has to fail; a no-op must not. `2` and `3` used to be the same number,
which left a wrapper script unable to tell its own bug from a human saying no.

That is the contract. Two places where today's code does not keep it, both in
[Limitations](https://velezanthony.github.io/docker-control-center/users/limitations/):

- `RC_CANCELLED` is returned from exactly one place, the `select` inside
  `pick()`. The written confirmations of `stack-rm` and `clean-hard` are
  `confirm || return 0`, so saying no exits `0`; and `confirm()` never checks
  for a terminal, so with no TTY the read fails, nothing is done and the command
  still exits `0`.
- The no-op rule holds for stacks and not for single containers. `stack-stop` on
  a stopped stack returns `0`, but `stop` resolves the name against `docker ps`:
  `dcc stop api` on an `api` that is already stopped answers *"There is no
  running container called 'api'"* with `1` — a false statement, and a `stop`
  that is not idempotent. `sh` takes the same path, where the restriction is the
  point.

## Releasing

The repository carries **zero tags**: nothing has ever been published, so this
workflow has never run. The first tag will also be its first execution.

The workflow refuses to publish if the tag and `DCC_VERSION` disagree, and it
reads `DCC_VERSION` **from the commit the tag points at** — so the bump has to be
committed *before* you tag, or the check aborts on the old number.

1. Bump `DCC_VERSION` in `src/scripts/common.sh`.
2. In `CHANGELOG.md`, turn `## [Unreleased]` into `## [x.y.z] — YYYY-MM-DD` and
   open a fresh empty `## [Unreleased]` above it.
3. Commit both.
4. Tag and push.

```bash
git commit -am "chore(release): 1.1.0"
git tag v1.1.0 && git push && git push --tags
```

`git push` before `git push --tags`: a tag whose commit is on no branch publishes
code nobody can find afterwards.

The workflow then runs `make check`, builds the single file, checks it starts
outside the repository, and uploads it as **`dcc`** — the name the README, both
landing pages and both installation pages tell people to download. A test keeps
the workflow and all five in agreement, in both directions.

## Testing destructive operations

On a throwaway stack, labelled as if it came from compose:

```bash
docker run -d --name test-a \
  --label com.docker.compose.project=test alpine sleep infinity
dcc stack-rm test
```

**Never** try `clean`, `clean-hard` or `kill-all` casually: they cannot be
scoped to a stack. And keep `volume-restore` off a machine you care about, for a
different reason — it *is* scoped, but it `rm -rf`s the volume's contents from
inside a container, asks **nothing**, and does not check whether a running
container has the volume mounted. Restore over a live database and you destroy
it, with the green ✓ and `0` of a job well done.

[Limitations](https://velezanthony.github.io/docker-control-center/users/limitations/)
lists what each of the seven destructive commands takes with it, and which two
of them ask first.
