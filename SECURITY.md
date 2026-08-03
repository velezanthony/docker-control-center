# Security Policy

## Supported versions

Security fixes are applied to the latest released version. Older versions are
not patched.

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅ |

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
- **Path traversal in backups.** `V=../../../tmp/x` wrote outside `BACKUP_DIR`.

If you find something in that family, it is a vulnerability and we want to know.

## What does not count

- Needing access to the Docker socket. Anyone who can talk to the daemon can
  already do anything on the host; that is Docker's model, not ours.
- The destructive commands doing what they say (`clean-hard`, `stack-rm`,
  `kill-all`). They ask for written confirmation where it matters.
