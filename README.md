# ping-ui

## Build

```sh
shards build
```

## Usage

```
bin/ping
```

## Database

- Ping samples are saved automatically while monitoring is running.
- The database file is stored at `~/.config/ping-ui/history.sqlite3` (or `$XDG_CONFIG_HOME/ping-ui/history.sqlite3` when set).
- Data is append-only by default and is not deleted automatically.

## Persisted Files

- `~/.config/ping-ui/history.sqlite3` (or `$XDG_CONFIG_HOME/ping-ui/history.sqlite3`):
	Stores ping sample history automatically while monitoring is active.
- `~/.config/ping-ui/settings.json` (or `$XDG_CONFIG_HOME/ping-ui/settings.json`):
	Stores app settings (thresholds, colors, recent hosts, notification options).
- Log export file (user-selected path via "Save Log..."):
	Saved only when you explicitly export logs from the menu.
