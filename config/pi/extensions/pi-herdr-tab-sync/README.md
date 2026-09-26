# pi-herdr-tab-sync

A [pi](https://pi.dev) extension that syncs the pi session name to the [herdr](https://herdr.dev) tab label.

## Behavior

- On **session resume** (`/resume`): if the session has a name, the herdr tab is renamed immediately.
- On **session name change** (e.g. `/name`): the herdr tab is updated immediately.
- On **agent start**: the tab label is synchronized as a fallback.
- If the session has **no name**, nothing happens — the tab label stays as-is.

Only activates inside herdr-managed panes (`HERDR_ENV=1`).

## Install

Copy or symlink into pi's global extensions directory:

```bash
ln -s ~/project/pi-herdr-tab-sync ~/.pi/agent/extensions/pi-herdr-tab-sync
```

Then `/reload` in pi or restart.

## License

MIT
