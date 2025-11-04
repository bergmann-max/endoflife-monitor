#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${script_dir}/.."
template_path="${script_dir}/template.html"
output_path="${script_dir}/index.html"
get_eol_script="${repo_root}/get_eol.sh"

error() {
    echo "ERROR: $*" >&2
}

if [[ ! -f "$template_path" ]]; then
    error "Template file not found at ${template_path}"
    exit 1
fi

if [[ ! -f "$get_eol_script" ]]; then
    error "get_eol.sh not found in repository root (${repo_root})"
    exit 1
fi

if [[ -x "$get_eol_script" ]]; then
    get_eol_cmd=("$get_eol_script")
else
    get_eol_cmd=(bash "$get_eol_script")
fi

html_escape() {
    local str="$1"
    str=${str//&/&amp;}
    str=${str//</&lt;}
    str=${str//>/&gt;}
    str=${str//\"/&quot;}
    printf '%s' "$str"
}

parse_csv_line() {
    local line="$1"
    local -n out_ref="$2"

    out_ref=()

    local length=${#line}
    local field=""
    local in_quotes=0
    local i=0

    while (( i < length )); do
        local char="${line:i:1}"
        if (( in_quotes )); then
            if [[ "$char" == '"' ]]; then
                local next="${line:i+1:1}"
                if [[ "$next" == '"' ]]; then
                    field+='"'
                    ((i++))
                else
                    in_quotes=0
                fi
            else
                field+="$char"
            fi
        else
            case "$char" in
                '"')
                    in_quotes=1
                    ;;
                ',')
                    out_ref+=("$field")
                    field=""
                    ;;
                *)
                    field+="$char"
                    ;;
            esac
        fi
        ((i++))
    done

    if (( in_quotes )); then
        error "Malformed CSV line encountered: $line"
        exit 1
    fi

    out_ref+=("$field")
}

generate_table_rows() {
    local line
    local rows=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        line="${line%$'\r'}"

        local fields=()
        parse_csv_line "$line" fields
        (( ${#fields[@]} == 0 )) && continue

        local label="${fields[0]:-}"
        local version="${fields[1]:-}"
        local category="${fields[2]:-}"
        local eol="${fields[3]:-}"

        local ordered_fields=()
        if (( ${#fields[@]} >= 4 )); then
            ordered_fields=("$label" "$version" "$category" "$eol")
        else
            ordered_fields=("${fields[@]}")
        fi

        local row="<tr class=\"odd:bg-indigo-50/30 even:bg-white transition-colors hover:bg-indigo-100/70\">"
        for field in "${ordered_fields[@]}"; do
            row+="<td class=\"px-4 py-3 align-top whitespace-normal text-gray-700\">$(html_escape "$field")</td>"
        done
        row+="</tr>"
        rows+="${row}"$'\n'
    done

    printf '%s' "$rows"
}

placeholder="<!--TABLE_ROWS-->"

template_content="$(<"$template_path")"

if [[ "$template_content" != *"$placeholder"* ]]; then
    error "Placeholder ${placeholder} not found in template."
    exit 1
fi

table_rows="$("${get_eol_cmd[@]}" "$@" | generate_table_rows)"

indent="        "
if [[ -z "$table_rows" ]]; then
    table_rows="<tr class=\"odd:bg-indigo-50/30 even:bg-white transition-colors hover:bg-indigo-100/70\"><td class=\"px-4 py-3 align-top whitespace-normal text-gray-700\" colspan=\"4\">No data</td></tr>"
else
    table_rows="${table_rows%$'\n'}"
    table_rows="${table_rows//$'\n'/$'\n'"$indent"}"
    table_rows="${indent}${table_rows}"
fi

output_content="${template_content//$placeholder/$table_rows}"
printf '%s' "$output_content" > "$output_path"

echo "Wrote ${output_path}"
