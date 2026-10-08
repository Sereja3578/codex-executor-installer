# Codex Executor Installer

This public repository contains the source of a local macOS setup application.
It is **not** the Codex Executor runtime source. The runtime payload is supplied
from a separate private checkout when building a release. The resulting app
contains Python runtime source files and must be treated as inspectable by
recipients, even though the source Git repository stays private.

The app guides a user through Homebrew dependencies, a separate OpenAI tunnel,
secure runtime-key storage in macOS Keychain, service setup and local health
checks. macOS file permissions and account sign-in always require the user's
own action. It does not bypass Gatekeeper or grant Full Disk Access itself.

Build from the canonical private source with:

```sh
./scripts/build.sh /absolute/path/to/private/codex-executor
```

The only release candidate is `dist/Codex Executor Installer.zip` in this
repository. A local, unsigned build is **not** ready for distribution. Before
publishing, sign with a Developer ID Application certificate, notarize the
archive, test on a clean second Mac, and review the embedded payload.

The app never creates a tunnel automatically: the user creates one in OpenAI
Platform, pastes its ID and runtime key, then connects it in ChatGPT. See the
[official Secure MCP Tunnel guide](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels).
