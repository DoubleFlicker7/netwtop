# Packaging documentation

These guides describe how to distribute `netwtop` through Debian's package
format and APT.

- [APT packaging and publishing](APT_PACKAGING.md) covers source preparation,
  Debian metadata, package contents, local validation, repository options, and
  the Debian submission path.
- [Self-hosted APT repository](SELF_HOSTED_APT_REPOSITORY.md) covers signing,
  `reprepro`, HTTPS publication, CI/CD, client configuration, operations, and
  key rotation for a project-owned repository.

The documents are operational guidance rather than files consumed by the
runtime. Keep example versions synchronized with [CHANGELOG.md](../../CHANGELOG.md)
when preparing a release.

