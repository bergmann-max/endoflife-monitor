# End-of-Life Monitor

Shell script that reads a list of products and versions from a CSV file,
queries the [endoflife.date](https://endoflife.date) API, and prints their End-of-Life (EOL) dates.

## Features

- Uses `products.csv` (or a custom CSV) with `product,version` rows.
- Automatically maps product names to the API format and retrieves the official label for each product.
- Emits results in `label,version,eol_date` format.

## Requirements

- Bash 4.0 or newer (`/usr/bin/env bash` shebang).
- `curl` for HTTP requests.
- `jq` for JSON parsing.

## Getting Started

```sh
git clone https://github.com/bergmann-max/endoflife-monitor.git
cd endoflife-monitor
chmod +x get_eol.sh
```

Update `products.csv` with the software you want to track or provide your own CSV file.

## Usage

Run the script from the repository root:

```sh
./get_eol.sh            # uses products.csv
./get_eol.sh mylist.csv # uses a custom CSV
./get_eol.sh --help     # prints usage details
```

Sample `products.csv`:

```csv
product,version
ubuntu,24.04
debian,12
debianGG,11
grafana,12.1
Pixel Watch,3
```

Typical output (date values depend on the API response):

```text
Ubuntu,24.04,2029-04-25
Debian,12,2028-06-30
Grafana,12.1,2025-08-27
```

## License

Released under the terms of the [Unlicense](LICENSE).
