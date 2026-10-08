# Codex Executor installer ownership

This repository contains the public macOS installer source only. The private,
canonical Executor source is at
`/Users/sergey/Library/Mobile Documents/com~apple~CloudDocs/Mac Downloads/Готовые скриптики/mcp/projects/codex-executor`.
Never develop or patch Executor runtime files here. Never copy the private Git
tree, credentials, local configuration, durable state, logs, or caches here.

The single distributable build location is this repository's `dist/` directory:
`dist/Codex Executor Installer.zip`. The build script accepts a private source
path and copies an explicit whitelist into the app bundle. It must never write
a release artifact to the private repository or another folder. Do not hand
out a build until it is Developer ID signed, notarized, tested on a clean Mac,
and its embedded payload hash matches the intended private source revision.

For every verified change to either repository, update the relevant Git
repository and rebuild this sole artifact when runtime or installer behavior
changes. Record the embedded source revision and local archive hash in
`BUILD_STATUS.md` after each rebuild. Do not blindly stage unrelated files.
Never push a build or source to
a public remote before confirming its payload exposure and reviewing the exact
staged diff. Never claim both repositories are synchronized without verifying
their remotes, commits, and the release manifest.
