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
  tests/              ShellSpec specs + spec_helper.sh + fixtures.sh
  i18n/en.sh es.sh    message catalogues
  commands.txt        which commands the product has, in what order and section

Makefile              development toolchain ONLY. It does not run the product.
build.sh              concatenates src/scripts/ into dist/
deps.sh               fetches vendor/ from dependencies.txt, verifying sha256
```

Three rules explain most of the design:

1. **`dashboard.sh` is the only source of presentation.** `ps`, `volumes`,
   `images` and `status` are views of it via `--only`.
2. **`ops.sh` is the only source of operations.** In the Makefile there is no
   shellcheck and nothing to test.
3. **The Makefile does not run the product.** It builds, tests and lints it.

## Adding things

| You add | You touch | How it works |
|---|---|---|
| A script | **nothing** | `build.sh` discovers the directory; `foo_main()` becomes `dcc foo`. Only touch `BUNDLE_ORDER` to decide **where** it is concatenated |
| An operation | `op_x()` + a line in `src/commands.txt` | dispatch derives from `declare -F op_*`. Two tests demand the line **and** its `help_x` catalogue key |
| A language | `src/i18n/xx.sh` | discovered by glob. Missing keys fall back to the key name |
| On-screen text | a catalogue key, via `t`/`tf` | never a literal. The **whole sentence** goes in the catalogue: "Choose a %s" produced *"Elige un imagen"* |
| A test | `src/tests/x_spec.sh` | copy the header of an existing spec: the DSL trips seven inherent shellcheck false positives and `make lint` fails without it. It disables both SC2317 and SC2329 — the same check under its old and new name, so it lints clean on 0.9.0 (what Ubuntu ships to CI) and on 0.11.0 |
| Test data | `src/tests/fixtures.sh` | invented, never from your `docker ps` |

Every script ends with the guard, in this exact three-line form — `strip_module`
matches exact lines:

```bash
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	foo_main "$@"
fi
```

## The suite is hermetic

No test may touch the Docker of the machine running it: `spec_helper.sh` defines
a `docker()` that fails with 127, so forgetting a stub is an error and not a
green run against someone's containers. Verified — same numbers with a fake
`docker`, with none on the `PATH`, and with a broken `DOCKER_HOST`.

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
| Scripts only run when launched directly | the `BASH_SOURCE` guard is what makes them testable **and** packageable |
| `make lint` leaves 2 cores free | it runs on a machine where someone is working |
| Docker's `.Reclaimable` is never used | it does not add up under containerd |
| CPU does not come from `docker stats` | that waits ~1 s between samples; cgroups take 500 ms |
| `declare -A x=()` and not `declare -A x` | without `=()` it is declared but unset and `${#x[@]}` blows up under `set -u` |
| `join_list` instead of `paste -sd', '` | `-d` takes a LIST that ROTATES: three items gave `a,b c` |
| No bash 5 without a fallback | the README promises bash 4+ |
| No `rg`, `sd` or `fd` | they ship with no distribution — a test watches for them |

## The single file

`make bundle` produces `dist/docker-control-center.sh`: a **concatenation**, not
a self-extractor. The `BASH_SOURCE` guard means the scripts only DEFINE when
pasted together; a dispatcher is appended at the end.

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
| `1` | what you named does not exist |
| `2` | usage error, or a missing value with no terminal to ask on |

A typo has to fail; a no-op must not.

## Releasing

Bump `DCC_VERSION` in `src/scripts/common.sh` and tag with the **same** number.
The workflow refuses to publish if they disagree.

```bash
git tag v1.1.0 && git push --tags
```

## Testing destructive operations

On a throwaway stack, labelled as if it came from compose:

```bash
docker run -d --name test-a \
  --label com.docker.compose.project=test alpine sleep infinity
dcc stack-rm test
```

**Never** try `clean`, `clean-hard` or `kill-all` casually: they cannot be
scoped to a stack.
