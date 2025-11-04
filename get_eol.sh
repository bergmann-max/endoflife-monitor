#!/usr/bin/env bash

set -euo pipefail

# === CONFIGURATION ===

# Rate limiting configuration
readonly RATE_LIMIT_DELAY_DEFAULT=0  # Default delay in seconds between API calls
RATE_LIMIT_DELAY="$RATE_LIMIT_DELAY_DEFAULT"

# Print error messages with a standard prefix, always to stderr
error() {
    echo "ERROR: $*" >&2
}

# Function to implement rate limiting
rate_limit() {
    if (( RATE_LIMIT_DELAY > 0 )); then
        sleep "$RATE_LIMIT_DELAY"
    fi
}

# Ensure required dependencies are available before running the script
for cmd in jq curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "$cmd is required but not installed"
        exit 1
    fi
done

readonly API_PRIMARY_URL="https://endoflife.date/api/v1/products"
readonly API_FALLBACK_URL="https://endoflife.date/api"

print_usage() {
    cat << EOF
Usage: ${0} [--rate-limit SECONDS] [CSV]

Options:
  -r, --rate-limit SECONDS  Delay in seconds between API calls (integer, default: ${RATE_LIMIT_DELAY_DEFAULT})
  -h, --help                Show this help

Description:
  This script checks End-of-Life (EOL) dates for products using the endoflife.date API.
  It reads a CSV file containing product and version information and outputs the
  corresponding label (product name), version, category, and EOL date for each product.

  The input CSV must be in "product,version" format.
  By default, "products.csv" is used if no file is specified.
  The output is in "label,version,category,eol_date" format for each entry.

EOF
}

INPUT_CSV=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_usage
            exit 0
            ;;
        -r|--rate-limit)
            VALUE="${2:-}"
            if [[ -z "$VALUE" ]]; then
                error "--rate-limit requires a value"
                print_usage >&2
                exit 2
            fi
            if [[ ! "$VALUE" =~ ^[0-9]+$ ]]; then
                error "--rate-limit expects an integer number of seconds (got '$VALUE')"
                exit 2
            fi
            RATE_LIMIT_DELAY="$VALUE"
            shift 2
            ;;
        --rate-limit=*)
            VALUE="${1#*=}"
            if [[ ! "$VALUE" =~ ^[0-9]+$ ]]; then
                error "--rate-limit expects an integer number of seconds (got '$VALUE')"
                exit 2
            fi
            RATE_LIMIT_DELAY="$VALUE"
            shift
            ;;
        --)
            shift
            POSITIONAL_ARGS+=("$@")
            break
            ;;
        -*)
            error "Unknown option: $1"
            exit 2
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ "${#POSITIONAL_ARGS[@]}" -gt 1 ]]; then
    error "Only one CSV file can be specified"
    exit 2
fi

if [[ "${#POSITIONAL_ARGS[@]}" -eq 1 ]]; then
    INPUT_CSV="${POSITIONAL_ARGS[0]}"
else
    INPUT_CSV="products.csv"  # Default CSV file
fi

# Check if the input CSV exists and is readable
if [[ ! -r "$INPUT_CSV" ]]; then
    error "Input CSV '$INPUT_CSV' not found or not readable."
    exit 2
fi

# === FUNCTIONS ===

# Fetches EOL info for a given product and version, outputs label, version, category, and EOL date
fetch_eol_info() {
    local PRODUCT="$1"
    local VERSION="$2"

    local API_PRODUCT
    API_PRODUCT=$(map_product "$PRODUCT")
    
    # Apply rate limiting
    rate_limit
    
    # Get product and version info (v1 endpoint preferred, legacy endpoint as fallback)
    local LABEL="$PRODUCT"
    local CATEGORY="null"
    local JSON
    if ! JSON=$(curl -sf --max-time 10 "${API_PRIMARY_URL}/${API_PRODUCT}/"); then
        if ! JSON=$(curl -sf --max-time 10 "${API_FALLBACK_URL}/${API_PRODUCT}.json"); then
            error "$LABEL,$VERSION,API request failed"
            return 1
        fi
    fi
    
    # Try to extract a human-friendly label from the primary response
    local META_INFO EXTRACTED_LABEL EXTRACTED_CATEGORY
    if META_INFO=$(echo "$JSON" | jq -r '
        if type == "object" then
            [
                (.result.label // .label // ""),
                (.result.category // .category // "")
            ]
        else
            ["",""]
        end | @tsv' 2>/dev/null); then
        IFS=$'\t' read -r EXTRACTED_LABEL EXTRACTED_CATEGORY <<< "$META_INFO"
        [[ -n "$EXTRACTED_LABEL" ]] && LABEL="$EXTRACTED_LABEL"
        if [[ -n "$EXTRACTED_CATEGORY" && "$EXTRACTED_CATEGORY" != "null" ]]; then
            CATEGORY="$EXTRACTED_CATEGORY"
        elif [[ "$EXTRACTED_CATEGORY" == "null" ]]; then
            CATEGORY="null"
        fi
    fi

    # Process the version data with a single jq call
    local VERSION_LABEL EOL_DATE VERSION_INFO
    if VERSION_INFO=$(echo "$JSON" | jq -r --arg ver "$VERSION" '
        def matches($ver):
            (.cycle == $ver) or
            (.name == $ver) or
            ((.name|tostring|startswith($ver)));
        def find_release($ver):
            try first(
                if type == "array" then
                    .[] | select(matches($ver))
                elif type == "object" then
                    .result.releases[]? | select(matches($ver))
                else
                    empty
                end
            ) catch null;
        find_release($ver) as $rel |
        [
            ($rel.releaseLabel // $rel.label // $rel.cycle // ""),
            ($rel.eol // $rel.eolFrom // $rel.eoasFrom // $rel.eoesFrom // "")
        ] | @tsv' 2>/dev/null); then
        IFS=$'\t' read -r VERSION_LABEL EOL_DATE <<< "$VERSION_INFO"
    fi
    [[ -z "$VERSION_LABEL" ]] && VERSION_LABEL="$VERSION"
    [[ -z "$EOL_DATE" ]] && EOL_DATE="null"

    # Output a robustly escaped CSV line
    jq -Rnr \
        --arg label "$LABEL" \
        --arg version "$VERSION_LABEL" \
        --arg category "$CATEGORY" \
        --arg eol "$EOL_DATE" \
        '[$label, $version, $category, $eol] | @csv'
}

# Converts product name to API format: lower-case, hyphen-separated.
map_product() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

# === MAIN LOGIC ===

EXIT_CODE=0

# Process each line as product,version, skipping header if present
while IFS=, read -r product version _; do
    # Skip header line
    if [[ "$product" =~ ^[[:space:]]*product[[:space:]]*$ ]] && \
       [[ "$version" =~ ^[[:space:]]*version[[:space:]]*$ ]]; then
        continue
    fi
    
    # Trim whitespace
    product="${product#"${product%%[![:space:]]*}"}"
    product="${product%"${product##*[![:space:]]}"}"
    version="${version#"${version%%[![:space:]]*}"}"
    version="${version%"${version##*[![:space:]]}"}"
    
    # Skip empty lines
    [[ -z "$product" || -z "$version" ]] && continue
    
    # Process the entry
    fetch_eol_info "$product" "$version" || EXIT_CODE=1
done < "$INPUT_CSV"

exit $EXIT_CODE
