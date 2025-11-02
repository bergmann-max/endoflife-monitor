#!/usr/bin/env bash

set -euo pipefail

# Ensure minimum bash version
if ((BASH_VERSINFO[0] < 4)); then
    echo "ERROR: This script requires bash version 4 or higher" >&2
    exit 1
fi

# === CONFIGURATION ===

# Rate limiting configuration
readonly RATE_LIMIT_DELAY=1  # Delay in seconds between API calls

# Print error messages with a standard prefix, always to stderr
error() {
    echo "ERROR: $*" >&2
}

# Function to implement rate limiting
rate_limit() {
    sleep "$RATE_LIMIT_DELAY"
}

# Ensure required dependencies are available before running the script
for cmd in jq curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "$cmd is required but not installed"
        exit 1
    fi
done

readonly API_BASE_URL="https://endoflife.date/api"
readonly API_LABEL_BASE_URL="https://endoflife.date/api/v1/products"

# Print usage/help and exit before touching input files
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    cat << EOF
Usage: ${0}                    # Uses default 'products.csv' in current directory
       ${0} products.csv        # Uses specified CSV file
       ${0} path/to/myproducts.csv

Options:
  -h, --help    Show this help

Description:
  This script checks End-of-Life (EOL) dates for products using the endoflife.date API.
  It reads a CSV file containing product and version information and outputs the
  corresponding label (product name), version, and EOL date for each product.

  The input CSV must be in "product,version" format.
  By default, "products.csv" is used if no file is specified.
  The output is in "label,version,eol_date" format for each entry.

EOF
    exit 0
fi

INPUT_CSV="${1:-products.csv}"  # Input CSV file (default: products.csv), must contain product,version lines

# Check if the input CSV exists and is readable
if [[ ! -r "$INPUT_CSV" ]]; then
    error "Input CSV '$INPUT_CSV' not found or not readable."
    exit 2
fi

SCRIPT_HAS_ERRORS=0  # Tracks if any error occurred, sets the exit code accordingly

# === FUNCTIONS ===

# Fetches EOL info for a given product and version, outputs label, version, and EOL date, or logs errors.
fetch_eol_info() {
    local PRODUCT="$1"
    local VERSION="$2"

    local API_PRODUCT
    API_PRODUCT=$(map_product "$PRODUCT") || { error "Failed to map product: $PRODUCT"; SCRIPT_HAS_ERRORS=1; return 1; }
    local API_URL="${API_BASE_URL}/${API_PRODUCT}.json"
    local LABEL_URL="${API_LABEL_BASE_URL}/${API_PRODUCT}/"
    
    # Apply rate limiting
    rate_limit

    local LABEL_JSON LABEL
    if ! LABEL_JSON=$(curl -sf --max-time 10 "$LABEL_URL"); then
        error "$PRODUCT,$VERSION,API label request failed"
        SCRIPT_HAS_ERRORS=1
        return 1
    fi
    if ! LABEL=$(echo "$LABEL_JSON" | jq -er '.result.label' 2>/dev/null); then
        LABEL="UNKNOWN"
    fi

    local JSON FIRST_CHAR EOL_DATE=""
    if ! JSON=$(curl -sf --max-time 10 "$API_URL"); then
        error "$LABEL,$VERSION,API product request failed"
        SCRIPT_HAS_ERRORS=1
        return 1
    fi

    FIRST_CHAR=$(echo "$JSON" | head -c 1)

    # The API may return either an array or an object as top-level JSON, handle both cases.
    if [[ "$FIRST_CHAR" == "[" ]]; then
        if ! EOL_DATE=$(echo "$JSON" | jq -e -r --arg ver "$VERSION" '
            .[] | select(
                (.cycle == $ver) or
                (.name == $ver) or
                ((.name|tostring|startswith($ver)))
            ) | .eol // .eolFrom // .eoasFrom // .eoesFrom' 2>/dev/null | head -n1); then
            error "$LABEL,$VERSION,EOL not found (array)"
            SCRIPT_HAS_ERRORS=1
            return 1
        fi
    elif [[ "$FIRST_CHAR" == "{" ]]; then
        if ! EOL_DATE=$(echo "$JSON" | jq -e -r --arg ver "$VERSION" '
            .result.releases[]? | select(
                (.cycle == $ver) or
                (.name == $ver) or
                ((.name|tostring|startswith($ver)))
            ) | .eol // .eolFrom // .eoasFrom // .eoesFrom' 2>/dev/null | head -n1); then
            error "$LABEL,$VERSION,EOL not found (object)"
            SCRIPT_HAS_ERRORS=1
            return 1
        fi
    else
        error "$LABEL,$VERSION,Invalid JSON"
        SCRIPT_HAS_ERRORS=1
        return 1
    fi

    # EOL_DATE must not be empty or null
    if [[ -z "$EOL_DATE" || "$EOL_DATE" == "null" ]]; then
        error "$LABEL,$VERSION,EOL not found"
        SCRIPT_HAS_ERRORS=1
        return 1
    else
        echo "$LABEL,$VERSION,$EOL_DATE"
        return 0
    fi
}

# Converts product name to API format: lower-case, hyphen-separated.
# Special handling for products with common aliases.
map_product() {
    local IN="$1"
    local LPRODUCT
    if [[ "${BASH_VERSINFO:-0}" -ge 4 ]]; then
        LPRODUCT="${IN,,}"
    else
        LPRODUCT=$(echo "$IN" | tr '[:upper:]' '[:lower:]')
    fi
    # Replace spaces with hyphens
    printf '%s\n' "${LPRODUCT// /-}"
}

# === MAIN LOGIC ===

# Process each line as product,version. Skip header if present.
{
    # Read first line to check if it's a header
    if IFS=, read -r first_product first_version _; then
        # Convert to lowercase for case-insensitive comparison
        first_product_lower=$(echo "$first_product" | tr '[:upper:]' '[:lower:]')
        first_version_lower=$(echo "$first_version" | tr '[:upper:]' '[:lower:]')
        
        # Process first line only if it's not a header
        if [[ ! "$first_product_lower" =~ ^[[:space:]]*product[[:space:]]*$ ]] || \
           [[ ! "$first_version_lower" =~ ^[[:space:]]*version[[:space:]]*$ ]]; then
            # Trim and process first line as normal data
            PRODUCT="${first_product#"${first_product%%[![:space:]]*}"}"
            PRODUCT="${PRODUCT%"${PRODUCT##*[![:space:]]}"}"
            VERSION="${first_version#"${first_version%%[![:space:]]*}"}"
            VERSION="${VERSION%"${VERSION##*[![:space:]]}"}"
            if [[ -n "$PRODUCT" && -n "$VERSION" ]]; then
                fetch_eol_info "$PRODUCT" "$VERSION"
            fi
        fi
    fi

    # Process remaining lines
    while IFS=, read -r PRODUCT VERSION _; do
        # Trim leading/trailing whitespace
        PRODUCT="${PRODUCT#"${PRODUCT%%[![:space:]]*}"}"
        PRODUCT="${PRODUCT%"${PRODUCT##*[![:space:]]}"}"
        VERSION="${VERSION#"${VERSION%%[![:space:]]*}"}"
        VERSION="${VERSION%"${VERSION##*[![:space:]]}"}"
        if [[ -z "$PRODUCT" || -z "$VERSION" ]]; then
            continue
        fi
        fetch_eol_info "$PRODUCT" "$VERSION"
    done
} < "$INPUT_CSV"

exit $SCRIPT_HAS_ERRORS
