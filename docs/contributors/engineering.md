# Production-grade Bash with ShellSpec

Design guide for tools written in pure Bash (>= 4.4) with ShellSpec as the test
framework. Every snippet on this page was **verified by running it** — not
written from memory. Minimum Bash versions are noted where they matter.

This page is about how the code is built. What the finished tool does **not**
do — the silent failures, the destructive commands, the dependencies it never
declares — is catalogued in [Limitations](../users/limitations.md).

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

!!! warning "This repository does not run that boilerplate, and it is deliberate"
    Every executable script here runs `set -uo pipefail` and nothing else —
    eight of the nine files in `src/scripts/`, plus `build.sh` and `deps.sh`.
    `common.sh` sets nothing at all: it is the library the others source.
    `set -e` is **banned** by [How to contribute](../contributing.md), because
    `pick()`, `confirm()` and `grep` return != 0 as a legitimate answer, and
    aborting on the first non-zero would abort on a user declining a menu.
    There is no `IFS=$'\n\t'` anywhere
    either, and no `trap ERR`: the product has two traps in total, an `EXIT`
    cleanup in `dashboard.sh` and a `RETURN` cleanup in `deps.sh`.

    The price is paid, not dodged. With no `-e`, `build.sh` reports a missing
    input on stderr, **exits `0`**, and writes the single file anyway: remove
    `src/commands.txt` and the bundle still builds, carrying `DCC_HELP_SRC=''`
    and therefore no help at all. Verified. Read §1 as the general rule and this
    box as the standing exception.

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

A file that separates defining from executing can be loaded from anywhere.

!!! danger "That guard does not survive concatenation"
    It is the guard everyone writes, and on its own it is **not enough to bundle
    with**. Paste two modules that carry it into one file and `BASH_SOURCE[0]`
    and `$0` are both that file, so every `main` fires in turn, in source order.
    Verified — two such modules plus a dispatcher, concatenated and run:

    ```console
    $ bash bundle.sh
    A RAN
    B RAN
    DISPATCHER
    ```

Bundling needs a second condition: an off switch the wrapper sets. Which is why
every script in `src/scripts/` ends with this, and not with the two-line form
above:

```bash
# Sourced: only DEFINES. Executed: RUNS.
# Inside the single file DCC_BUNDLE is set, so the guard switches itself off.
if [ -z "${DCC_BUNDLE:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	main "$@"
fi
```

`build.sh` writes `DCC_BUNDLE=1` into the header of the generated file. The
modules pasted below it only define, and the dispatcher appended at the end is
the only thing that runs. Two files sit outside the rule on purpose:
`bundle-main.sh`, whose guard is the inverse (`[ -n "${DCC_BUNDLE:-}" ]`, so it
runs **only** inside the bundle), and `common.sh`, a library with no entry point
and no guard at all.

---

## 4. Advanced testing with ShellSpec

### Unit vs black box

| | Unit (`When call`) | Black box (`When run`) |
|---|---|---|
| Subshell | **no** | **yes** |
| Variables after the call | **visible** | **lost** |
| kcov coverage | **measured** | **also measured** |
| Use for | internal functions | whole scripts, CLIs |

`When run` on a project function **is** measured — verified: a single
`When run dex_main` covered 31 lines of `dex.sh`. What kcov cannot see is a
separate **process** (`When run bash -c …`, or the bundle that `bundle_spec.sh`
launches), because it instruments this suite and not its children.

**Two more blind spots, and they pull in opposite directions.**

A **one-line function never enters the report at all.** `f() { g; return; }`
puts the body on the definition line, and kcov instruments neither: the function
comes out neither covered nor uncovered — it leaves the denominator. In `ops.sh`
that is every `op_ctx()   { docker context ls; }` in the file, so the script is
scored over noticeably fewer lines than it actually has. Write the same function
across three lines and it does appear: `op_engine()` sits in the report with
`hits=0`. The compact style this guide defends below buys readability and pays
for it in coverage you cannot see.

The inverse artefact: **an `awk` or `jq` program inside a shell string is counted
as bash.** Those lines never run as bash, so they are reported uncovered however
well the function is tested. `dcc_parse_commands()` has its own `Describe` in
`common_spec.sh`; the line holding the `awk` invocation shows plenty of hits and
the lines of awk program below it all read `hits=0`. Same in `dashboard.sh`,
where `fmt_status()` is entered constantly and every line of `awk` inside it
reports zero — a good part of why that file's percentage looks low, and why
splitting it in two would not move it by a single line.

Run `make coverage` and open `coverage/index.html` to see both artefacts for
yourself. Do not take the percentage at face value in either direction.

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

**One file, `bundle_spec.sh`, costs close to half the wall clock**, every time
anyone has measured it. It builds the single file and runs it as a separate
process, several times over. That ratio is the finding worth writing down.

**The seconds are not, so this guide does not publish them.** Time it yourself
when you need it:

```bash
time make test        # everything
time make test-fast   # everything except bundle_spec.sh
```

And do not write the answer down. Measuring this suite without changing a line
of it has produced times varying by almost **3×** on one machine in a single
afternoon. A previous version of this section published a range that looked
prudent; the very next run fell outside it.

`/proc/loadavg` does not save you either — it is a one-minute average, so it
lags a machine that has just gone quiet. The fastest run ever recorded here
reported the *highest* load.

Parallelism does not save you either: `--jobs` barely moved the clock, because
ShellSpec parallelises **per file** and one file dominates. Amdahl wins. Split
the file or accept the wall clock.

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
make test-fast                            # the development loop
make test                                 # pre-commit and CI
./vendor/shellspec/shellspec --tag slow   # the tagged block, on demand
```

That third line carries its path for a reason: ShellSpec is **vendored, not
installed**. `make deps` puts it in `vendor/shellspec/shellspec` and there is no
`shellspec` on your `PATH` — the same holds for every bare `shellspec` in the
option table above. And the tag is **not** the exact complement of `test-fast`:
`bundle_spec.sh` opens a second `Describe` that carries no tag, so `--tag slow`
runs fewer examples than `test-fast` skips, and those extra ones belong to
neither loop.

!!! tip "Every timing this guide ever published turned out to be wrong"
    The first version quoted two figures taken with another stopwatch running in
    parallel over the same suite — inflated several times over. The second was
    measured on a supposedly quiet machine and doubled the moment an editor was
    open. The third was a deliberately cautious *range*, and the next run
    escaped it.

    The conclusion held every single time: one file dominates and `--jobs` will
    not fix it. The numbers never did. That is why they are gone, and why the
    only instruction here is `time make test` at the moment you care.

### `shfmt` destroys more than you think

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
the readability of the nesting, which is the whole point of the DSL.

**And it is not only the specs.** This project excluded `*_spec.sh` and kept a
`make fmt` for the scripts — until someone measured it: `shfmt -d` produced
**1333 lines of diff across all nine scripts** on a tree nobody had touched
(**1437** today, with shfmt 3.13.1 and its defaults — the figure depends on the
version and the flags, so quote both). It cannot leave a one-line function
alone:

```diff
-f() { g; return; }
+f() {
+	g
+	return
+}
```

That compact form is deliberate — it is what lets seven one-line operations read
at a glance. So the target was deleted. **A formatter you have to warn people
not to run is not a formatter.** `shellcheck` is the style authority here; it
has an opinion about correctness and none about where your braces go.

### Mandatory `shellcheck` header in specs

The DSL triggers seven **inherent** false positives:

```bash
# shellcheck shell=bash
#
#  `Parameters` rows are DATA, not commands:
#   SC2286  an empty cell ("") looks like an empty command name
#   SC2288  a cell starting with an odd character looks like a command
#   SC2215  a cell such as -9000000 looks like a command flag
#
#  The DSL calls and shares state in ways shellcheck cannot follow:
#   SC2317  a function body inside an `It` looks unreachable
#   SC2329  the same check under its new name, from 0.10.0 on
#   SC2034  what `setup()` writes is read in another block
#   SC2154  `MAP[key]` is a literal KEY, not a variable to resolve
#
# shellcheck disable=SC2034,SC2154,SC2215,SC2286,SC2288,SC2317,SC2329
```

`SC2317` and `SC2329` are **the same check renamed**, so both go in: 0.9.0 is
what Ubuntu ships to CI and only knows the old name, while a local 0.11.0 only
knows the new one. Drop either and the suite lints clean on one machine and red
on the other.

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

`make deps` vendors exactly one thing: ShellSpec. Three more tools have to be on
your machine already, and none of them is declared in `dependencies.txt`:

| Tool | Needed by | Missing |
|---|---|---|
| `shellcheck` | `make lint`, so also `make check` and the hook | Checked first; you get the project's own message |
| `kcov` | `make coverage` | Checked first; the project's own message |
| `jq` | `make lint`, so also `make check` and the hook | **No guard.** Raw `jq: command not found`, then `make: *** [lint] Error 1` |

Because `make lint` is not only shellcheck. Before it lints anything it
validates `bytes.jq` and `metrics.jq` with `jq -n` — `metrics.jq` with
`bytes.jq` prepended, because on its own it fails with *"h/0 is not defined"*.
That loop calls `jq` directly, so on a machine with the vendored ShellSpec but no `jq`, `make check`
dies at its first target with an error from the interpreter and not a word of
the project's own. Verified.

Git submodules were tried and rejected: they nest a second Git repository inside
yours — duplicated panels in the editor, a `clone --recursive` everyone forgets,
and accidental commits into someone else's code.

### CI pipeline

```yaml
# .github/workflows/ci.yml — trimmed here; the reasoning lives in the real file
name: CI
on:
  push: { branches: [main, development] }
  pull_request:

# Without this, three pushes in a row leave three full runs going and nobody
# cancels the old ones. Except on main, where every commit wants its own result.
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}

jobs:
  check:                                 # bash 5, mawk
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: sudo apt-get update && sudo apt-get install -y shellcheck jq
      - run: make check                  # lint and tests behind one target

      # The bundle is checked separately: a broken single file is not caught by
      # anyone until a user downloads it.
      - run: make bundle
      - name: The single file starts outside the repository
        run: cp dist/docker-control-center.sh /tmp/dcc && cd /tmp && ./dcc version

  # The README promises bash 4+. Running only on the runner — bash 5.2 — checks
  # the letter of the rule without ever running the promised configuration.
  #
  # ubuntu:18.04 and NOT the `bash:4.4` image: that one is Alpine and ships
  # busybox awk, so it would mix two different incompatibilities into one red
  # cross. 18.04 gives bash 4.4 with mawk, which is exactly what the README says.
  #
  # And `docker run` rather than `container:`, because actions/checkout needs
  # node inside the container and these images do not have it.
  bash4:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: |
          docker run --rm -v "$PWD:/repo" -w /repo ubuntu:18.04 sh -c '
            apt-get update -qq && apt-get install -y -qq make curl ca-certificates
            # `bash -n` is the part of `make check` that DOES depend on the
            # version: this is where bash 5 syntax gets caught.
            for f in src/scripts/*.sh src/tests/*.sh build.sh deps.sh; do
              bash -n "$f" || exit 1
            done
            make test
          '

  # The code claims to avoid GNU extensions so it behaves the same with mawk and
  # gawk. The runners ship mawk, so gawk was never exercised.
  gawk:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: |
          sudo apt-get update && sudo apt-get install -y gawk
          sudo update-alternatives --set awk /usr/bin/gawk
      - run: make test
```

Three jobs, three promises the README makes. There is deliberately **no coverage
job**: kcov runs locally with `make coverage`, and a number that nobody is
allowed to lower is a number that ends up gamed.

Testing the minimum bash is not optional in a tool that advertises one. In this
project `EPOCHREALTIME` (bash 5.0) slipped into the code and aborted a whole
script on bash 4, under `set -u`, without saying why. The `bash4` job would have
caught it on the first push.

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
make lint                  # validates the .jq files, then shellcheck; no formatter
make coverage              # kcov -> coverage/
make check                 # lint + parse + tests: run before committing
```

`deps` needs the network; `lint` and `check` need `shellcheck` **and** `jq`;
`coverage` needs `kcov`. Only ShellSpec is vendored for you.
