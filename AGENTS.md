# Notes for coding agents

## Changelog

CurseForge uses `CHANGELOG.md` as the changelog for each release (see `manual-changelog` in `.pkgmeta`). It does not use the git log.

- With every user-visible change, add a line to `CHANGELOG.md` saying what changed, in plain words for players.
- Put it under the section for the next release. If the top section's version is already tagged, start a new `## <version>` section above it. Tags look like `1.0.3`, without a "v".
- Write only what changed. No commit hashes, author names, emails or co-author lines.
- Leave out changes players can't see, such as README edits, line endings or refactors.
