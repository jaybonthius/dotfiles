# Subagent host loading

`index.ts` loads the installed `pi-subagents` extension after setting its supported `PI_SUBAGENTS_PI_CODING_AGENT_PACKAGE_ROOT` override from the running SDK's `getPackageDir()`. This fixes SDK hosts such as Pi Web, whose launcher is not the Pi CLI and whose SDK is outside the extensions' npm directory. An explicit override is preserved; Bun standalone discovery stays with upstream.

The package remains in `settings.base.json` for installation, skills and prompts, with its automatic extension entry disabled to avoid duplicate registration. The directory is already deployed by the existing extensions symlink.

The `0.69.0` pin preserves compatibility with Pi Web's Pi SDK `0.85.1`. Version `0.70.1` imports newer `pi-ai` helpers that this host does not export; the `0.71.0` changelog explicitly raises the supported host minimum to `0.86.1`. Upgrade the pin with the host SDK, and validate an actual asynchronous child—not just tool registration or package resolution.
