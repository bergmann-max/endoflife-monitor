# End-of-Life Monitor

Shell script that reads a list of products and versions from a CSV file,
queries the [endoflife.date](https://endoflife.date) API, and prints their End-of-Life (EOL) dates.

## Features

- Uses `products.csv` (or a custom CSV) with `product,version` rows for input.
- Emits results in `label,version,eol_date` format.
- Optional rate limiting between API calls via `--rate-limit`.

## Requirements

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
./get_eol.sh                 # uses products.csv
./get_eol.sh mylist.csv      # uses a custom CSV
./get_eol.sh --rate-limit 2  # waits 2 seconds between API calls
./get_eol.sh --help          # prints usage details
```

Sample `products.csv`:

```csv
product,version
debian,13
ubuntu,24.04
ansible,12
grafana,12.2
kubernetes,1.34
iphone,17
apple-watch,series-11
pixel,10pro
Pixel Watch,4
```

output:

```
$ ./get_eol.sh
"Debian","13 (Trixie)","2028-08-09"
"Ubuntu","24.04 'Noble Numbat' (LTS)","2029-04-25"
"Ansible","12","null"
"Grafana","12.2","2026-06-23"
"Kubernetes","1.34","2026-10-27"
"Apple iPhone","17","null"
"Apple Watch","Series 11","null"
"Google Pixel","Pixel 10 Pro","2032-08-01"
"Google Pixel Watch","Pixel Watch 4","2028-10-01"
```

## License

[Unlicense](LICENSE).
