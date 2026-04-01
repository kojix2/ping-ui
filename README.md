# ping

A ping activity monitor built with Crystal and UIng. It has a target input and GO/STOP controls at the top, with a 4-row timeline chart and console log at the bottom.

## Installation

```sh
shards install
```

## Usage

```sh
crystal run src/ping.cr
```

The app uses native ICMP echo from Crystal (no external `ping` process required on macOS).

Display rules:

- Green: success
- Yellow: short failure streak
- Orange: medium failure streak
- Red: long failure streak

The four chart rows represent: since launch, last 1 hour, last 10 minutes, and last 1 minute.

STOP pauses monitoring only; history and console logs are preserved.

You can also open Settings from the menu to customize:

- failure-streak thresholds (spinboxes)
- chart colors (color pickers)

## Development

```sh
crystal spec
crystal build src/ping.cr
```

## Contributing

1. Fork it (<https://github.com/kojix2/ping-ui/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [kojix2](https://github.com/kojix2) - creator and maintainer
