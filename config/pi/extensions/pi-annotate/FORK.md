# SSH-tunnel transport fork

This directory vendors the runtime from upstream [`pi-annotate@0.5.0`](https://www.npmjs.com/package/pi-annotate/v/0.5.0). Commit `64749420f8fa77d4913c1af9a298752c1c6044ac` was copied from and compared against the installed 0.5.0 runtime, excluding only upstream marketing files `banner.png` and `demo.mp4`.

The fork keeps Pi's `/tmp/pi-annotate.sock` and `/tmp/pi-annotate.token` protocol. A persistent Bun relay on Linux owns that interface while a browser is connected and bridges newline-delimited Pi messages to a Chrome extension WebSocket on `127.0.0.1:43173`. The Mac browser initiates the WebSocket through an existing SSH connection; Chrome native messaging is not used.

Add this line to the relevant Mac SSH host entry, then keep that SSH connection open:

```sshconfig
LocalForward 127.0.0.1:43173 127.0.0.1:43173
```

Load this unpacked extension in Chrome 116 or newer:

```text
~/dotfiles/config/pi/extensions/pi-annotate/chrome-extension
```

The Linux Home Manager configuration starts `pi-annotate-relay.service` with the Nix-provided Bun on personal machines. It deliberately does not manage the Mac SSH host entry.

Review only the transport-fork delta with:

```bash
git diff 64749420f8fa77d4913c1af9a298752c1c6044ac..HEAD
```
