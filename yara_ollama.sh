#!/bin/bash
# Wazuh - YARA active response with Ollama
# Copyright (C) 2015-2024, Wazuh Inc.

# This program is free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.

#------------------------- Configuration -------------------------#

# Ollama API endpoint
OLLAMA_API_URL="http://85.90.245.104:11434/api/chat"
OLLAMA_MODEL="qwen3:0.6b"

# Set LOG_FILE path
LOG_FILE="logs/active-responses.log"

#------------------------- Gather parameters -------------------------#

read INPUT_JSON
YARA_PATH=$(echo $INPUT_JSON | jq -r .parameters.extra_args[1])
YARA_RULES=$(echo $INPUT_JSON | jq -r .parameters.extra_args[3])
FILENAME=$(echo $INPUT_JSON | jq -r .parameters.alert.syscheck.path)

size=0
actual_size=$(stat -c %s "${FILENAME}")
while [ ${size} -ne ${actual_size} ]; do
    sleep 1
    size=${actual_size}
    actual_size=$(stat -c %s "${FILENAME}")
done

#----------------------- Analyze parameters -----------------------#

if [[ -z "$YARA_PATH" ]] || [[ -z "$YARA_RULES" ]]; then
    echo "wazuh-YARA: ERROR - YARA active response error. YARA path and rules parameters are mandatory." >> "${LOG_FILE}"
    exit 1
fi

#------------------------- Main workflow --------------------------#

YARA_output="$("${YARA_PATH}/yara" -w -r -m "$YARA_RULES" "$FILENAME")"

if [[ -n "$YARA_output" ]]; then
    # Attempt to delete the file
    if rm -rf "$FILENAME"; then
        echo "wazuh-YARA: INFO - Successfully deleted $FILENAME" >> "${LOG_FILE}"
    else
        echo "wazuh-YARA: INFO - Unable to delete $FILENAME" >> "${LOG_FILE}"
    fi

    while read -r line; do
        description=$(echo "$line" | grep -oP '(?<=description=").*?(?=")')

        if [[ -n "$description" ]]; then
            # Prepare JSON payload
            payload=$(jq -n \
                --arg model "$OLLAMA_MODEL" \
                --arg content "In one paragraph, tell me about the impact and how to mitigate \"$description\"" \
                '{
                    model: $model,
                    messages: [
                        {
                            role: "system",
                            content: "You are a security expert."
                        },
                        {
                            role: "user",
                            content: $content
                        }
                    ]
                }')

            # Query Ollama API
            ollama_response=$(curl -s -X POST "$OLLAMA_API_URL" \
                -H "Content-Type: application/json" \
                -d "$payload")

            # Extract response text
            response_text=$(echo "$ollama_response" | jq -r '.message.content')

            if [[ -z "$response_text" || "$response_text" == "null" ]]; then
                echo "wazuh-YARA: ERROR - Ollama API returned empty response: $ollama_response" >> "${LOG_FILE}"
            else
                combined_output="wazuh-YARA: INFO - Scan result: $line | ollama_response: $response_text"
                echo "$combined_output" >> "${LOG_FILE}"
            fi
        else
            echo "wazuh-YARA: INFO - Scan result: $line" >> "${LOG_FILE}"
        fi
    done <<< "$YARA_output"

else
    echo "wazuh-YARA: INFO - No YARA rule matched." >> "${LOG_FILE}"
fi

exit 0
