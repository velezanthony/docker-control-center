# Language

The interface is in **English and Spanish**. With nothing configured it picks
itself from your `$LANG`: if it is `es_*` you get Spanish, otherwise English.

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
DCC_LANG=es make dash      # just this once
```

Full precedence:

```
DCC_LANG from the environment  >  ~/.config/dcc/config  >  $LANG  >  English
```

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

Copy `i18n/en.sh` to `i18n/<code>.sh`, translate the values, and add the
detection in `scripts/common.sh`. Missing keys fall back to the key name, so a
half-finished translation breaks nothing.
