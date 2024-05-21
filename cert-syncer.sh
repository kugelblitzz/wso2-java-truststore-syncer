#!/bin/bash

# Paths to the source and destination truststores
SRC_TRUSTSTORE="/path/to/source/client-truststore.jks"
DEST_TRUSTSTORE="/path/to/destination/client-truststore.jks"
PASSWORD="your_keystore_password"

# Aliases to exclude from syncing
EXCLUDE_ALIASES=("alias1" "alias2")

# Function to check if an alias is in the exclude list
is_excluded() {
    local alias=$1
    for excluded in "${EXCLUDE_ALIASES[@]}"; do
        if [[ "$excluded" == "$alias" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to check if an alias exists in the destination truststore
alias_exists_in_dest() {
    local alias=$1
    keytool -list -keystore "$DEST_TRUSTSTORE" -storepass "$PASSWORD" -alias "$alias" &> /dev/null
    return $?
}

# Function to show progress indicator
show_progress() {
    local message=$1
    local pid=$2
    local -a spinners=('|' '/' '-' '\')
    while kill -0 $pid 2>/dev/null; do
        for spinner in "${spinners[@]}"; do
            echo -ne "\r$message $spinner"
            sleep 0.1
        done
    done
}

# List all aliases in the source truststore using -rfc option for better parsing
ALIASES=$(keytool -list -keystore "$SRC_TRUSTSTORE" -storepass "$PASSWORD" -rfc | grep 'Alias name:' | awk -F': ' '{print $2}')

# Arrays to hold the summary information
MISSING_CERTS=()
SKIPPED_CERTS=()

for ALIAS in $ALIASES; do
    if is_excluded "$ALIAS"; then
        SKIPPED_CERTS+=("$ALIAS")
        continue
    fi
    
    if alias_exists_in_dest "$ALIAS"; then
        SKIPPED_CERTS+=("$ALIAS")
        continue
    fi

    # Show progress with borders and color
    BORDER="\033[1;34m--------------------------------------------------\033[0m"
    echo -e "\n$BORDER"
    echo -e "\033[1;32mProcessing alias: $ALIAS\033[0m"
    echo -e "$BORDER"

    # Export the certificate from the source truststore
    keytool -exportcert -keystore "$SRC_TRUSTSTORE" -storepass "$PASSWORD" -alias "$ALIAS" -file /tmp/"$ALIAS".cer &
    PROGRESS_PID=$!
    show_progress "Exporting alias: $ALIAS" $PROGRESS_PID

    # Wait for the export process to finish
    wait $PROGRESS_PID
    echo -ne "\rExporting alias: $ALIAS ... \033[1;32mExported\033[0m\n"

    # Import the certificate into the destination truststore
    keytool -importcert -keystore "$DEST_TRUSTSTORE" -storepass "$PASSWORD" -alias "$ALIAS" -file /tmp/"$ALIAS".cer -noprompt &
    PROGRESS_PID=$!
    show_progress "Importing alias: $ALIAS" $PROGRESS_PID

    # Wait for the import process to finish
    wait $PROGRESS_PID
    echo -ne "\rImporting alias: $ALIAS ... \033[1;32mImported\033[0m\n"

    # Remove the temporary certificate file
    rm /tmp/"$ALIAS".cer

    # Add to the missing certs list
    MISSING_CERTS+=("$ALIAS")

    echo -ne "Processing alias: $ALIAS ... \033[1;32mDone\033[0m\n\n"
done

# Function to draw a horizontal line
draw_line() {
    printf '+%s+\n' "$(printf '%*s' "${COLUMNS:-$(tput cols)}" '' | tr ' ' '-')"
}

# Display summary with colors and line columns
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
HEADER_COLOR='\033[1;34m'
BORDER_COLOR='\033[1;34m'

echo
echo "Certificate sync completed."
echo
draw_line
printf "${HEADER_COLOR}| %-50s | %-10s |\n" "ALIAS" "STATUS"
draw_line

for ALIAS in "${MISSING_CERTS[@]}"; do
    printf "| %-50s | ${GREEN}%-10s${NC} |\n" "$ALIAS" "Imported"
done

for ALIAS in "${SKIPPED_CERTS[@]}"; do
    printf "| %-50s | ${YELLOW}%-10s${NC} |\n" "$ALIAS" "Skipped"
done

draw_line
