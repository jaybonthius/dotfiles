# Subagent host loading

`index.ts` loads the installed `pi-subagents` extension after setting its supported `PI_SUBAGENTS_PI_CODING_AGENT_PACKAGE_ROOT` override from the running SDK's `getPackageDir()`. This fixes SDK hosts such as Pi Web, whose launcher is not the Pi CLI and whose SDK is outside the extensions' npm directory. An explicit override is preserved; Bun standalone discovery stays with upstream.

The package remains in `settings.base.json` for installation, skills and prompts, with its automatic extension entry disabled to avoid duplicate registration. The directory is already deployed by the existing extensions symlink.

## Native Gerbil MCP

On personal x86_64 Linux machines, Home Manager adds `mcp:gerbil` to the configured roles through the standard `tools` allowlist described in [pi-subagents' tool-selection documentation](https://github.com/nicobailon/pi-subagents/blob/main/docs/agents.md#tool-and-extension-selection). `config/pi/subagent-mcp-tools.json` preserves the other installed tool capabilities; keep it aligned with the package and extension configuration. Home Manager leaves other platforms' inheritance unchanged, applies machine-local overrides last, and omits interactive-only tools from the Discord profile. No MCP-loading shim or installed-package patch is needed. Reload Pi and start fresh children after switching.

Native MCP selection requires Pi 0.99 or later and pi-subagents 0.74.0 or later. The former 0.69.0 pin accommodated Pi Web's older SDK; it is no longer configured. Validate a real child after upgrades, not just package resolution.
