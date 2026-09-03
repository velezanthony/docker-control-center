# Security Policy

## Supported versions

Security fixes are applied to the latest released version. Older versions are
not patched.

| Version | Supported |
|---------|-----------|
| `main`  | ✅ |

**Nothing has been released yet** — the repository carries no tags, so `main` is
the only thing anyone can be running. This table will list real versions once
there is a release.

## Reporting a vulnerability

Please **do not open a public issue**. Use
[GitHub's private vulnerability reporting](https://github.com/velezanthony/docker-control-center/security/advisories/new).

## What counts as a vulnerability here

This tool runs `docker` commands with the arguments you give it, so the
interesting surface is what happens when those arguments are not what you
expected. Real examples from this project's own history:

- **Names were not validated.** `docker run -v "$name":/data` treats anything
  starting with `/` as a **bind mount of the host**, so a mistyped volume name
  turned `volume-restore` into an `rm -rf` on whatever directory you named.
  Names are now checked against what actually exists.
- **`volume-restore` deleted before verifying.** `rm -rf /data/* && tar xzf`
  meant a corrupt backup left you with no volume *and* no backup. The archive
  is verified first.
- **Path traversal in backups.** A volume named `../../../tmp/x` wrote outside
  `BACKUP_DIR`.

If you find something in that family, it is a vulnerability and we want to know.

## What does not count

- Needing access to the Docker socket. Anyone who can talk to the daemon can
  already do anything on the host; that is Docker's model, not ours.
- The destructive commands doing what they say. Only two of the seven ask
  anything, and without a terminal even those auto-deny in silence and exit
  `0`. Documented behaviour rather than a vulnerability — the table of all
  seven and the `confirm()` mechanics are in
  [Limitations](https://velezanthony.github.io/docker-control-center/users/limitations/#commands-that-destroy-things).
  Do not treat a written confirmation as a safeguard outside an interactive
  shell.

## Known gaps

The three worked examples above were fixed. These two are still open, and both
are described in full — mechanism, blast radius and workaround — in
[Limitations](https://velezanthony.github.io/docker-control-center/users/limitations/).

- **`volume-restore` asks nothing.** The most destructive command here wipes a
  volume's contents with no confirmation of any kind and no check that anything
  has it mounted, so a restore over a live database destroys its data without
  asking
  ([detail](https://velezanthony.github.io/docker-control-center/users/limitations/#volume-restore-asks-nothing)).
- **The helper image is not pinned.** `volume-tree`, `volume-backup`,
  `volume-backup-all` and `volume-restore` hand your volume to `HELPER_IMAGE` —
  `alpine` by default, a floating tag pulled from Docker Hub on first use, not
  a digest — and restore mounts it read-write, as root
  ([detail](https://velezanthony.github.io/docker-control-center/users/limitations/#the-helper-container)).

## Download integrity

There is nothing to verify yet, because nothing has been published. When
releases do start, the workflow as it stands uploads the executable and nothing
else: no sha256, no signature, no attestation. The install recipe it writes into
the release notes downloads a `.sh` with `curl` and runs it.

The build is reproducible byte for byte — two consecutive `build.sh` runs on
this machine produced the same sha256 — so publishing a checksum is cheap. It
is simply not being published today. Until it is, nothing about a downloaded
`dcc` is verifiable beyond where you got it from; cloning the repository and
running `make link` is the only install path with no unverified file in it.
