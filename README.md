# ping-ui

Desktop ping monitor written in Crystal.

## Build

```sh
shards build
```

## Run

```sh
bin/ping
```

## Storage

- History database: ~/.config/ping-ui/history.sqlite3
- Settings file: ~/.config/ping-ui/settings.json
- If XDG_CONFIG_HOME is set, both files are stored under $XDG_CONFIG_HOME/ping-ui/

## Data Handling

- Ping history is appended to the database.
- Old data is not deleted automatically.
