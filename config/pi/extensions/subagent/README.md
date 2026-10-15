# Subagent host loading

`index.ts` loads the installed `pi-subagents` extension after setting its supported `PI_SUBAGENTS_PI_CODING_AGENT_PACKAGE_ROOT` override from the running SDK's `getPackageDir()`. This fixes SDK hosts such as Pi Web, whose launcher is not the Pi CLI and whose SDK is outside the extensions' npm directory. An explicit override is preserved; Bun standalone discovery stays with upstream.

The package remains in `settings.base.json` for installation, skills and prompts, with its automatic extension entry disabled to avoid duplicate registration. The directory is already deployed by the existing extensions symlink.
