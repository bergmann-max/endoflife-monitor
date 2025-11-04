# End-of-Life Monitor

Shell script that reads a list of products and versions from a CSV file,
queries the [endoflife.date](https://endoflife.date) API, and prints their End-of-Life (EOL) dates.
The script emits machine-friendly CSV output so you can feed it directly into other tools or automation,
but you can just as well run it manually and inspect the results in your terminal.

## Features

- Uses `products.csv` (or a custom CSV) with `product,version` rows for input.
- Emits results in `label,version,category,eol_date` format.
- Returns `null` for `eol_date` whenever endoflife.date has not yet published that product version's EOL date.
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
"Debian","13 (Trixie)","os","2028-08-09"
"Ubuntu","24.04 'Noble Numbat' (LTS)","os","2029-04-25"
"Ansible","12","app","null"
"Grafana","12.2","server-app","2026-06-23"
"Kubernetes","1.34","server-app","2026-10-27"
"Apple iPhone","17","device","null"
"Apple Watch","Series 11","device","null"
"Google Pixel","Pixel 10 Pro","device","2032-08-01"
"Google Pixel Watch","Pixel Watch 4","device","2028-10-01"
```

---

## Static website script

`html/create_eol_html.sh` builds a static HTML report based on the CSV output from `get_eol.sh` and writes the result to `html/index.html` using `html/template.html` as the base.

```sh
./html/create_eol_html.sh                # uses products.csv via get_eol.sh
```

## More info

https://endoflife.date
https://endoflife.date/docs/api/v1/

## License

[Unlicense](LICENSE)
