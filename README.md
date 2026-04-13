# ping-ui

<div align="center">
  <img src="resources/app_icon.png" height="80" width="80" alt="ping-ui icon">
</div>

[![build](https://github.com/kojix2/ping-ui/actions/workflows/build.yml/badge.svg)](https://github.com/kojix2/ping-ui/actions/workflows/build.yml)


Desktop ping monitor written in Crystal.

## Build

```sh
shards build
```

Windows build is intended to work with Crystal for MinGW64. A GitHub Actions workflow is included to validate that the project still builds on Windows.

macOS app bundle and DMG:

```sh
./build-mac.sh
```

Generated artifacts are placed in dist/.

## Run

```sh
bin/ping
```

## Windows Status

- Windows support is implemented on a best-effort basis and should build against Crystal MinGW64.
- ICMP monitoring uses the Windows IcmpSendEcho API instead of raw sockets.
- Windows desktop notifications are not implemented yet.
- Packaging for Windows is not implemented yet.

## Storage

- History database: ~/.config/ping-ui/history.sqlite3
- Settings file: ~/.config/ping-ui/settings.json
- If XDG_CONFIG_HOME is set, both files are stored under $XDG_CONFIG_HOME/ping-ui/
- On Windows, both files are stored under %APPDATA%/ping-ui/ when APPDATA is available.

## Data Handling

- Ping history is appended to the database.
- Old data is not deleted automatically.
