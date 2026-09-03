# Language

The interface is in **English and Spanish**, and only those two. With nothing
configured it picks itself from your locale — and it matches on the **region**,
not only on the language: `es`, `es_ES`, `es-AR` and `es.UTF-8` all give you
Spanish, and so do `ca_ES`, `gl_ES`, `eu_ES` and even `en_ES`, because they end
in `_ES`. Everything else falls back to English.

Whichever one you end up with, part of the output is never translated, and one
usage line is hardcoded in Spanish no matter what you choose.
[Limitations](limitations.md#language) lists exactly which.

## Changing it

=== "Repository"
    ```bash
    make lang           # menu
    make lang en        # straight to it
    make lang auto      # back to auto-detection
    ```

=== "Single file"
    ```bash
    dcc lang
    dcc lang en
    dcc lang auto
    ```

```
  Current language: es Español (detected from your system locale)

  Choose a language:
1) en — English          3) auto — detect it from the system
2) es — Español

>
```

It changes the language of **every** command. It is saved in
`~/.config/dcc/config`, following the XDG standard: it is yours, not the
project's, and it survives updating the tool.

## For a single command

```bash
DCC_LANG=es make run dash      # just this once
```

Full precedence:

```
DCC_LANG  >  ~/.config/dcc/config  >  $LC_ALL  >  $LC_MESSAGES  >  $LANG  >  English
```

The three locale variables are read in that order, the same one the C library
uses. `LC_ALL` is the one that catches people out: exported by a script or a CI
job, it wins over the `LANG` you set yourself. And it decides more than the
language: under a non-UTF-8 locale such as `LC_ALL=C` the padding counts bytes,
so the accented Spanish columns drift —
[Limitations](limitations.md#output-and-terminal) has the numbers.

!!! warning "Do not export `DCC_LANG`"
    If you leave it exported in your terminal it will shadow the file and
    `lang` will look broken. Use it in front of a specific command, as above.
    If it happens, `lang` tells you and hands you the `unset`.

!!! question "Why a file and not just a variable?"
    A child process cannot modify its parent's environment. If `lang` ran
    `export`, that variable would die with the process and your terminal would
    never know. No command can change an environment variable for you — but it
    can write a file that every script reads on startup.

## Adding a language

Copy `src/i18n/en.sh` to `src/i18n/<code>.sh`, translate the values, and add
your code to the `case` in `dcc_load_language()`, in `src/scripts/common.sh`.
Then run `make bundle`: the single file carries the catalogues embedded and will
not see the new one until it is rebuilt.

Three things that will not warn you:

- **The catalogue alone is not a language.** `dcc lang <code>` accepts any code
  that exists as a file in `src/i18n/`, so if you skip the `case` you still get
  `✓ Language set to Français.`, the preference saved and exit code `0` — in
  English, because `apply()` reloads the language before printing it. From then
  on everything comes out in English and `dcc version` reports
  `language en (config)`. The ✓ is green and nothing complains.
- **There is no fallback to English.** `dcc_load_language()` does `MSG=()` and
  loads one catalogue and only one, so a key you forget reaches the user as its
  own name: `op_started`.
- **The parity test will not look at your file.** The one in
  `src/tests/common_spec.sh` has `en.sh` and `es.sh` hardcoded. Extend it with
  your language, or a half-finished translation passes `make check` in green.
