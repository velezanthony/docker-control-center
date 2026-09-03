<!--
Thanks for the PR. Remove any section that does not apply.
The full map, conventions and comment doctrine live in CONTRIBUTING.md.
-->

## What this changes

<!-- One or two sentences. -->

## Why

<!-- Link an issue (`Fixes #123`) or describe the motivation. -->

## How

<!-- Only if the approach is not obvious from the diff. -->

## Checklist

- [ ] `make check` passes locally — that is lint, `bash -n` and the whole suite
- [ ] Tests added or updated, and they fail without the change
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] Docs updated if user-facing behaviour changed, **and the `.es.md`
      translation with them** — `.md` is English, `.es.md` is Spanish
- [ ] A new limitation, or one this removes, is reflected in
      `docs/users/limitations.md` and its translation

If you touched a script under `src/scripts/`:

- [ ] No bash 5 syntax without a fallback — the README promises bash 4+
- [ ] No GNU-only `awk` (`\s`, `[[:space:]]`, `gensub`…) — the `gawk` CI job
      runs the same code that `mawk` 1.3.3 does
- [ ] Nothing the user has to install added to the runtime — and no `rg`, `sd`,
      `fd`, `bat` or `eza`, which ship with no distribution
- [ ] Screen text does not hardcode `make`; the prefix comes from `$DCC_CMD`
- [ ] The entry point still ends with the `DCC_BUNDLE` guard, or the bundle and
      the tests both break

## Anything else

<!-- Trade-offs, follow-up work, anything a reviewer should know. -->
