# Matched Pi browser runtime

Pi continues to install and update `npm:pi-agent-browser-native`. Its entry in `settings.base.json` disables direct extension loading (`extensions: []`); the adjacent `../browser-runtime` package loads it after preparing its exact CLI. Home Manager exposes this directory as `~/.pi/browser-runtime`, shared by interactive and Discord Pi settings.

The loader imports the upstream factory through Pi's loader, reads the loaded runtime's `TARGET_AGENT_BROWSER_VERSION`, installs that exact `agent-browser` version if necessary, verifies `--version`, and prepends its version-specific bin directory to the Pi process's PATH. Older packages without runtime target exports use their published capability baseline. The global npm install under `PI_CODING_AGENT_DIR` is the selected extension source; arbitrary project-local or explicit `-e` browser package overrides are outside this loader.

CLI installations live under `${XDG_CACHE_HOME:-~/.cache}/pi-agent-browser/<platform>-<arch>/<version>`. A cold installation needs npm/network access; cache hits do not. Installs use a private staging directory and are published by atomic rename only after version verification. Concurrent starts cannot expose half-installed packages. Lifecycle scripts are disabled because upstream's postinstall can rewrite an unrelated global CLI symlink; the packaged upstream launcher already selects and makes its native binary executable.

Different Pi processes may use different matched versions. A running process retains both its upstream factory and CLI selection through `/reload`, matching upstream's documented compiled-module caching. `pi update --extensions` remains the normal update command; restart Pi to load the updated extension and automatically provision its matching CLI. Old CLI versions are not automatically deleted or upgraded underneath running sessions. Browser profiles, Chromium selection, authentication, and upstream tool behavior are unchanged.

`~/bin/agent-browser` uses the same cache for standalone commands and the upstream doctor, selecting the target from the active Pi home on each invocation. Pi's native tool instead uses its process-pinned bin directory first. No pnpm-global browser version pin should remain in `home.nix`.

## Validation

```sh
node --test config/pi/browser-runtime/test/*.test.mjs
node ~/.pi/agent/npm/node_modules/pi-agent-browser-native/scripts/doctor.mjs
PI_CODING_AGENT_DIR="$HOME/.pi/discord-agent" node ~/.pi/discord-agent/npm/node_modules/pi-agent-browser-native/scripts/doctor.mjs
```

Offline startup (`--offline` or `PI_OFFLINE=1`) uses a cached CLI but never downloads a missing version. Failed installs leave working versions untouched. If the upstream metadata or package layout changes incompatibly, setup fails explicitly rather than guessing a version or falling back to an unrelated global CLI.

## Source documentation

- [Pi packages: local sources, filtering, and updates](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/packages.md)
- [Pi extensions: awaited async factories and host imports](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/extensions.md)
- [Browser package: installation, exact version policy, and doctor](https://github.com/fitchmultz/pi-agent-browser-native#readme)
- [Canonical upstream target](https://github.com/fitchmultz/pi-agent-browser-native/blob/main/scripts/agent-browser-target.mjs)
- [Compiled-module caching across reload](https://github.com/fitchmultz/pi-agent-browser-native/blob/main/docs/SUPPORT_MATRIX.md)
