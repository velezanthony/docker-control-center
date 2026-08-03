# Production-grade Bash with ShellSpec

Design guide for tools written in pure Bash (>= 4.4) with ShellSpec as the test
framework. Every snippet on this page was **verified by running it** — not
written from memory. Minimum Bash versions are noted where they matter.

!!! warning "This repository promises Bash 4.0, not 4.4"
    The guide assumes 4.4+. This project declares **4+** in its README, so
    `${var@Q}` (4.4), `local -n` (4.3) and `BASH_ARGV0` (5.0) cannot be used in
    `src/scripts/` without a fallback. A test enforces it
    (`src/tests/bundle_spec.sh`). If you raise the requirement, that test is
    where it is recorded.

---

## 1. Environment hardening and strict mode

### The boilerplate

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
```

| Flag | What it does | Why |
|---|---|---|
| `-e` | abort on the first failing command | a silent error halfway through a destructive script is worse than aborting |
| `-u` | unset variable is an error | `rm -rf "$DIR/"` with an empty `DIR` wipes the root |
| `-o pipefail` | a pipeline fails if any stage fails | without it, `failing_cmd \| tee log` returns 0 |
| **`-E`** | **the ERR trap is inherited by functions and subshells** | **without this your error handler never fires where it matters** |
| `IFS=$'\n\t'` | drops space from the separator | avoids accidental word splitting on paths with spaces |

`-E` (`errtrace`) is the one almost everyone omits. **Verified:**

```console
$ bash -c 'set -euo pipefail; trap "echo TRAP" ERR; f(){ false; }; f'
(nothing)                  # without -E the trap does NOT enter the function

$ bash -c 'set -Eeuo pipefail; trap "echo TRAP" ERR; f(){ false; }; f'
TRAP
```

### Global traceback with `trap ERR`

```bash
_traceback() {
	local rc=$1 cmd=$2 line=$3 i
	printf '\n[ERROR] rc=%s at line %s: %s\n' "$rc" "$line" "$cmd" >&2
	printf 'Stack (most recent first):\n' >&2
	for ((i = 1; i < ${#FUNCNAME[@]} - 1; i++)); do
		printf '  %s() at %s:%s\n' \
			"${FUNCNAME[i]}" "${BASH_SOURCE[i+1]##*/}" "${BASH_LINENO[i]}" >&2
	done
}
trap '_traceback "$?" "$BASH_COMMAND" "$LINENO"' ERR
```

Real output:

```
[ERROR] rc=1 at line 16: false
Stack (most recent first):
  level_3() at tb.sh:17
  level_2() at tb.sh:18
  level_1() at tb.sh:19
```

The three magic arrays, and the offset you must respect:

- `FUNCNAME[i]` — the function name at level `i`
- `BASH_LINENO[i]` — the line **from which** `FUNCNAME[i]` was called
- `BASH_SOURCE[i+1]` — the file holding that call. **`i+1`, not `i`**:
  `BASH_SOURCE[i]` is where the function is *defined*, not where it is *called*.

Arguments are passed **positionally** (`"$?" "$BASH_COMMAND" "$LINENO"`). Reading
them inside `_traceback` would yield the handler's own values.

### Cleanup with `trap EXIT`

`EXIT` always fires: clean exit, `set -e` abort, or explicit `exit`. **Verified**
— the `false` aborts and cleanup still runs:

```console
$ bash -c 'set -Eeuo pipefail; tmp=$(mktemp -d); trap "rm -rf $tmp; echo CLEANED" EXIT; false'
CLEANED
```

Declare the trap **immediately** after creating the resource:

```bash
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT     # here, not three lines below
```

For several resources, accumulate into an array. A second `trap ... EXIT`
**replaces** the first, it does not stack:

```bash
declare -a _CLEANUP=()
_cleanup() { local p; for p in "${_CLEANUP[@]:-}"; do rm -rf "$p"; done; }
trap _cleanup EXIT

tmp=$(mktemp -d);  _CLEANUP+=("$tmp")
other=$(mktemp -d); _CLEANUP+=("$other")
```

### The three holes in `set -e`

`set -e` is **not** a complete safety net. It switches itself off in three places:

```bash
# 1. In a condition: the failure is the data, not an error
if process; then ... fi           # -e does NOT apply inside process
process && echo ok                # nor here

# 2. `local` masks the exit status
local x=$(false)                  # rc of `local` is 0. The failure vanishes.
local x; x=$(false)               # correct: rc of the command

# 3. Only the last stage of a pipeline counts, unless pipefail
false | true                      # rc=0 without pipefail
```

Number 2 does the most damage because it looks identical to the correct form.

---

## 2. Defensive typing

Bash has no types. It does have **variable attributes**, and using them is the
difference between a script and a tool.

### `declare` attributes

```bash
declare -i counter=0        # integer: counter+=1 adds, does not concatenate
declare -a list=()          # indexed array
declare -A map=()           # associative array (dictionary)
declare -r CONSTANT="fixed" # read-only
declare -n ref=other_var    # nameref (Bash 4.3+)
```

`declare -i` saves the most silent grief:

```bash
declare -i n=5; n+=1     # -> 6
declare    s=5; s+=1     # -> "51"   <- the classic bug
```

### Scope: `declare` inside a function is LOCAL

**This is Bash's number one trap and it fails silently.** Verified:

```console
$ bash -c 'f(){ declare -r C=1; }; f; echo "outside: C=${C:-<unset>}"'
outside: C=<unset>
```

The dangerous case is `-A`:

```bash
load() { declare -A MAP; }   # MAP dies on return
load
MAP[key]="value"             # MAP is no longer associative: it is INDEXED
```

And it does not blow up. An indexed array evaluates `MAP[key]` as **arithmetic**,
gets `0`, and **every key writes to the same slot**. The program does not crash —
it returns the wrong value.

Rules:

- The global `declare -A/-a` goes **outside** every function.
- Inside functions, always `local` — including loop counters.
- Need a global from inside a function? `declare -g` (Bash 4.2+).

### Guard functions with semantic exit codes

Return distinct codes per error class. A blanket `1` tells the caller nothing:

```bash
readonly E_OK=0 E_TYPE=64 E_RANGE=65 E_FORMAT=66 E_MISSING=67

# assert_is_int <value> [name]
assert_is_int() {
	local v=${1-} name=${2:-value}
	[[ -n $v ]]            || { printf '%s: empty\n'        "$name" >&2; return "$E_MISSING"; }
	[[ $v =~ ^-?[0-9]+$ ]] || { printf '%s: not an int: %q\n' "$name" "$v" >&2; return "$E_TYPE"; }
	return "$E_OK"
}

# assert_in_range <value> <min> <max>
assert_in_range() {
	local v=$1 min=$2 max=$3
	assert_is_int "$v" || return
	(( v >= min && v <= max )) \
		|| { printf 'out of [%s,%s]: %s\n' "$min" "$max" "$v" >&2; return "$E_RANGE"; }
}

# assert_is_email <value>
assert_is_email() {
	local v=${1-}
	[[ $v =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] \
		|| { printf 'invalid email: %q\n' "$v" >&2; return "$E_FORMAT"; }
}
```

Three details that are not cosmetic:

- `${1-}` rather than `${1:-}` distinguishes "not passed" from "passed empty",
  and survives `set -u`.
- `[[ $v =~ ... ]]` with the pattern **unquoted**: quoting turns it into a literal.
- `%q` when printing the bad value: a value with newlines or escapes will not
  mangle your log.

For JSON there is no honest validation without `jq`. Do not fake it:

```bash
assert_is_json() {
	command -v jq >/dev/null || { printf 'jq is not installed\n' >&2; return "$E_MISSING"; }
	printf '%s' "${1-}" | jq -e . >/dev/null 2>&1 \
		|| { printf 'invalid JSON\n' >&2; return "$E_FORMAT"; }
}
```

### "Objects" with namerefs

`local -n` (Bash 4.3+) passes a variable **by reference**. It is the closest
thing to a struct Bash offers. **Verified:**

```bash
# new_server <var_name> <host> <port>
new_server() {
	local -n _obj=$1
	_obj=([host]="$2" [port]="$3" [state]="stopped")
}

server_url() {
	local -n _obj=$1
	printf 'https://%s:%s' "${_obj[host]}" "${_obj[port]}"
}

declare -A web
new_server web example.com 8443
server_url web        # -> https://example.com:8443
```

!!! danger "The nameref name collision"
    If the caller uses a variable with the **same name** as the nameref, Bash
    aborts with *"circular name reference"*. Always prefix namerefs (`_obj`,
    `__ref`) and never use that prefix outside.

    ```bash
    f() { local -n obj=$1; ...; }
    declare -A obj; f obj      # <- blows up
    ```

Alternative without namerefs, Bash 4.0 compatible: one global dictionary with
compound keys.

```bash
declare -A OBJECTS
OBJECTS[web.host]="example.com"
OBJECTS[web.port]="8443"
```

---

## 3. Modularity and namespaces

### Absolute path resolution

A relative `source` depends on the directory you were invoked from. Always
resolve against the **file**, never the cwd:

```bash
_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/log.sh
. "$_DIR/lib/log.sh"
```

- `cd --` and `dirname --` guard against paths starting with `-`.
- `pwd -P` resolves symlinks: two paths to the same file stop being two paths.
- The `# shellcheck source=...` comment is **mandatory**, or shellcheck cannot
  follow the module and `-x` stops being useful.

### Import guard

```bash
[[ -n ${_LIB_LOG_LOADED:-} ]] && return 0
readonly _LIB_LOG_LOADED=1
```

Without it, a module loaded twice re-runs its initialisation and a top-level
`readonly` aborts the whole script.

### Namespaces

Bash has none. Simulate them with prefixes, and be disciplined:

| Element | Convention | Example |
|---|---|---|
| Public function | `module::func` or `module_func` | `log::info` |
| Private function | `_module_func` | `_log_format` |
| Constant | `UPPERCASE` + `readonly` | `readonly LOG_LEVEL_INFO=2` |
| Module variable | `_MODULE_STATE` | `_LOG_TARGET` |

`log::info` is valid in Bash and reads far better. `declare -F` still sees it, so
dynamic dispatch keeps working.

When something must be **truly** isolated, wrap it in a subshell:

```bash
result=$( set -eu; cd "$dir"; process )   # cd and variables never escape
```

It costs a fork. Use it when isolation matters more than speed.

### The "main" pattern

All testability rests on separating **defining** from **executing**:

```bash
main() {
	local action=${1:-help}
	case "$action" in
		run)  _do_something ;;
		*)    _usage; return 2 ;;
	esac
}

# Sourced: only DEFINES. Executed: RUNS.
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
	main "$@"
fi
```

A file that separates defining from executing can be loaded from anywhere. That
same property is what lets you **bundle** every module into a single `.sh` by
concatenation: pasted together they only define, and a dispatcher is appended at
the end.

---

## 4. Advanced testing with ShellSpec

### Unit vs black box

| | Unit (`When call`) | Black box (`When run`) |
|---|---|---|
| Subshell | **no** | **yes** |
| Variables after the call | **visible** | **lost** |
| kcov coverage | **measured** | no |
| Use for | internal functions | whole scripts, CLIs |

**Verified:**

```sh
It 'When call: the variable SURVIVES'
  set_it() { SEEN="yes"; }
  When call set_it
  The variable SEEN should eq "yes"
End

It 'When run: the variable does NOT survive'
  set_it() { SEEN="yes"; }
  When run set_it
  The variable SEEN should be undefined
End
```

**Practical consequence:** if you record calls to a double in a **variable** and
evaluate with `run`, the assertion "docker was not called" passes green even when
it was. Record to a **file**.

### Mocking external commands

```sh
Describe 'deploy'
  Include src/deploy.sh

  setup() {
    LOG="$SHELLSPEC_TMPBASE/calls.log"; : >"$LOG"
    # Function-based double: free, and the recommended one.
    curl()      { printf 'curl %s\n'      "$*" >>"$LOG"; printf '{"ok":true}'; }
    systemctl() { printf 'systemctl %s\n' "$*" >>"$LOG"; return 0; }
    docker()    { printf 'docker %s\n'    "$*" >>"$LOG"; return 0; }
  }
  BeforeEach 'setup'

  calls() { [ -s "$LOG" ] && printf '%s' "$(<"$LOG")"; return 0; }

  It 'restarts the service after deploying'
    When call deploy v2
    The result of function calls should include "systemctl restart"
  End

  It 'does NOT touch systemctl when the download fails'
    failure() { curl() { return 22; }; deploy v2; }
    When call failure
    The status should be failure
    The result of function calls should be blank
  End
End
```

Two ways to double, and when to use each:

| | Function | `Mock ... End` |
|---|---|---|
| Cost | none | writes a real script into `PATH` |
| Reach | current shell and its subshells | also child processes (`bash -c`, `xargs`) |
| When | **by default** | the code invokes the command in another process |

Both are restored when the block closes: no leakage between examples.

### Asserting `stderr`, `status` and your type guards

```sh
Describe 'assert_is_int()'
  Include src/lib/assert.sh

  Describe 'accepts integers'
    Parameters
      0
      42
      -7
    End
    It "accepts '$1'"
      When call assert_is_int "$1"
      The status should be success
    End
  End

  Describe 'rejects with the right semantic code'
    Parameters
      "3.14" 64 "a decimal is a TypeError"
      "abc"  64 "text is a TypeError"
      ""     67 "empty is Missing, not Type"
    End
    It "$3"
      When call assert_is_int "$1" age
      The status should eq "$2"
      The stderr should include "age"
      The stdout should be blank
    End
  End
End
```

`The stdout should be blank` is not filler: a validator that pollutes standard
output breaks every `x=$(...)` that wraps it.

### Three verified traps

**1. `Parameters` applies to the WHOLE `Describe`, not the next `It`.**

```sh
# WRONG: the second It inherits the first table and runs 5 times
Describe 'pct()'
  Parameters ... End
  It "..." ... End
  Parameters ... End      # does not replace: it merges
  It "..." ... End
End

# RIGHT: each table in its own nested Describe
Describe 'pct()'
  Describe 'normal cases'
    Parameters ... End
    It "..." ... End
  End
  Describe 'edge cases'
    Parameters ... End
    It "..." ... End
  End
End
```

**2. `Include` resolves `declare -A` scope; a hand-written `source` does not.**
Load the module inside `setup()` and the `declare -A` dies on return (§2), so the
dictionary silently becomes indexed. Always use `Include`.

**3. Control characters in `When` arguments break the reporter.**
If your code uses `\x1f` (or any control separator) and you pass it through
`When call fn "$SEP" ...`, ShellSpec aborts with:

```
reporter.sh: line 216: field_: command not found
1 example, 0 failures            <- the test PASSES
Fatal error ... exit status 102  <- and the run aborts anyway
```

Fix: keep the character from crossing the `When` boundary; use it inside the
helper function.

### `satisfy` expects a function name

```sh
The output should satisfy [ "$(cat)" -ge 16 ]   # WRONG: '[' is not function name
```

Move the condition into a function and assert the status:

```sh
It 'returns microseconds'
  is_micros() { local n; n=$(with_epoch); [ "${#n}" -ge 16 ]; }
  When call is_micros
  The status should be success
End
```

---

## 5. Engineering environment (DX)

### A professional `.shellspec`

```
--load-path src/tests
--require spec_helper
--default-path src/tests

# The scripts use declare -A, [[ ]] and arrays: bash, not POSIX sh.
--shell bash

# Scope coverage or kcov instruments ShellSpec itself.
--kcov-options "--include-path=src/scripts/"
--kcov-options "--exclude-pattern=/src/tests/,/vendor/,.jq"
```

Options worth knowing, by context:

| Option | When |
|---|---|
| `--jobs N` | large suites; parallelises **per file** |
| `--tag TAG` | run only the tagged examples (see the warning below) |
| `--format documentation` | read the suite as a specification |
| `--format tap` / `--format junit` | CI integration |
| `--fail-fast` | red-green-refactor loop |
| `--random examples` | surface hidden dependencies between examples |

### Split the slow tests out

Measured on this repository, 237 examples, machine idle:

```
bundle_spec.sh     20.0 s     <- builds and runs the bundle N times
dashboard_spec.sh   1.9 s
ops_spec.sh         1.0 s
common_spec.sh      0.9 s
whole suite        ~25 s
```

**One file is 80 % of the time.** Which is why parallelism barely helps:

```
serial:     ~25.0 s
--jobs 8:    22.4 s      <- 11 % better, not 8x
```

ShellSpec parallelises **per file**. With one dominant file, Amdahl wins.

Tags are **extra arguments on the block**, not a directive:

```sh
Describe 'the single file' slow:true    # correct
Describe 'the single file'
  Set 'slow:true'                        # WRONG: Set is for shell options.
End                                      # Aborts with exit 102.
```

!!! danger "`--tag` only INCLUDES, it cannot exclude"
    `--tag slow:no` does **not** mean "everything but the slow ones". It looks
    for examples whose tag literally equals `slow:no` and returns **0 examples**.
    Verified. If your fast loop "takes 5 seconds", check it is running anything.

So the fast loop filters by **file**:

```make
test-fast: $(SHELLSPEC)
	@$(SHELLSPEC) $(filter-out %/bundle_spec.sh,$(wildcard $(SRC)/tests/*_spec.sh))
```

```bash
make test-fast         # ~5 s: the development loop
make test              # ~25 s: pre-commit and CI
shellspec --tag slow   # only the slow ones, when you need them
```

!!! tip "Measure on an idle machine"
    The first version of this table said 96 s and 120 s. It was taken with
    another stopwatch running in parallel over the same suite: the figures came
    out **5× inflated**. The conclusion (one file dominates, `--jobs` will not
    fix it) held; the numbers did not. Re-measure before quoting.

### `shfmt` DESTROYS spec files

**Verified.** `shfmt` does not understand `Describe`/`It`/`End` as block
structure: it treats them as loose commands and flattens the whole DSL to column 0.

```diff
 Describe 'best_match()'
-	Include src/scripts/dex.sh
-	best()  { best_match "$1" <<<"$LIST" | cut -f1; }
+Include src/scripts/dex.sh
+best()  { best_match "$1" <<<"$LIST" | cut -f1; }
```

It does not break execution (indentation is cosmetic in shell) but it destroys
the readability of the nesting, which is the whole point of the DSL. **Exclude
`*_spec.sh` from `shfmt`.**

### Mandatory `shellcheck` header in specs

The DSL triggers six **inherent** false positives:

```bash
# shellcheck shell=bash
#
#  `Parameters` rows are DATA, not commands:
#   SC2286  an empty cell ("") looks like an empty command name
#   SC2288  a cell starting with an odd character looks like a command
#   SC2215  a cell such as -9000000 looks like a command flag
#
#  The DSL calls and shares state in ways shellcheck cannot follow:
#   SC2329  functions inside an `It` are called indirectly by `When call`
#   SC2034  what `setup()` writes is read in another block
#   SC2154  `MAP[key]` is a literal KEY, not a variable to resolve
#
# shellcheck disable=SC2034,SC2154,SC2215,SC2286,SC2288,SC2329
```

Disable them **in the spec header**, never in a global `.shellcheckrc` — that
would also silence them in production code, which is where they matter.

### Dependencies: prefer a verified manifest

ShellSpec ships an official installer and it works
(`sh install.sh 0.28.1 --prefix ./vendor`), but `grep -ci 'sha256|gpg'` over it
returns **0**: the documented pattern is `curl … | sh` with no verification at
all, and it keeps all 3.7 MB.

A plain manifest plus a small installer closes that hole and generalises to the
next dependency:

```
# name  version  sha256  url  [paths,to,keep]
shellspec 0.28.1 400d8354… https://…/0.28.1.tar.gz shellspec,lib,libexec,helper,stub,bin
```

The installer verifies the checksum and **aborts without extracting** if it does
not match. `vendor/` is generated output and belongs in `.gitignore`, like
`dist/`. Package managers (`bpkg`, `basher`) do not help here: you have to
install them globally first, which is a dependency to manage dependencies.

Git submodules were tried and rejected: they nest a second Git repository inside
yours — duplicated panels in the editor, a `clone --recursive` everyone forgets,
and accidental commits into someone else's code.

### CI pipeline

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push: { branches: [main] }
  pull_request:

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: ShellCheck
        run: shellcheck -x -S style src/scripts/*.sh src/tests/*_spec.sh

      # -d = diff: fails if anything is unformatted, rewrites nothing.
      # Specs are excluded: shfmt does not understand the DSL.
      - name: shfmt (check, do not rewrite)
        run: |
          curl -fsSL -o /tmp/shfmt \
            https://github.com/mvdan/sh/releases/download/v3.10.0/shfmt_v3.10.0_linux_amd64
          chmod +x /tmp/shfmt
          /tmp/shfmt -d -ln bash -i 0 -ci src/scripts/*.sh build.sh deps.sh

      # Dependencies come from the manifest, with their sha256 verified.
      - name: Dependencies
        run: make deps

      - name: Tests
        run: make test

  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: sudo apt-get update && sudo apt-get install -y kcov
      - run: make deps && make coverage
      - uses: actions/upload-artifact@v4
        with: { name: coverage, path: coverage/ }

  # The README promises Bash 4+. An untested promise is not a promise.
  compatibility:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        bash: ["4.4", "5.0", "5.2"]
    container: bash:${{ matrix.bash }}
    steps:
      - uses: actions/checkout@v4
      - run: apk add --no-cache make git curl tar coreutils
      - run: make deps && make test
```

The version matrix is not optional for a tool that advertises a minimum Bash. In
this project `EPOCHREALTIME` (Bash 5.0) slipped into the code and aborted a whole
script on Bash 4, under `set -u`, without saying why. A matrix would have caught
it on the first push.

### Pre-commit hook

```bash
make hooks     # writes .git/hooks/pre-commit -> make check
```

`make check` = `lint` + parse + `test`. Cheap to run, expensive to skip.

---

## Antipatterns to avoid

| Antipattern | Instead |
|---|---|
| `for f in $(ls *.txt)` | `for f in *.txt; do [[ -e $f ]] \|\| continue` |
| `[ $x = "y" ]` | `[[ $x == "y" ]]` — no word splitting |
| `expr $a + $b` | `$(( a + b ))` |
| `cat f \| grep x` | `grep x f` |
| `echo $var` | `printf '%s\n' "$var"` — `echo` interprets escapes per shell |
| `local x=$(cmd)` | `local x; x=$(cmd)` — otherwise the exit status is lost |
| `cd dir` unchecked | `cd dir \|\| return 1` |
| `[[ $v =~ "$pattern" ]]` | `[[ $v =~ $pattern ]]` — quoting makes it literal |
| `rm -rf "$DIR/"` with `DIR` possibly empty | `set -u` + `assert_not_empty "$DIR"` |
| Double recording to a variable + `When run` | record to a file |

---

## Command reference

```bash
make deps                  # fetch vendor/, verifying sha256
make test                  # whole suite
make test T=common         # a single file
make test-fast             # everything but the slow bundle spec
make lint                  # shellcheck
make fmt                   # shfmt (specs excluded)
make coverage              # kcov -> coverage/
make check                 # lint + parse + tests: run before committing
```
