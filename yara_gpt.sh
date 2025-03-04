#!/bin/bash
# Wazuh - YARA active response
# Copyright (C) 2015-2024, Wazuh Inc.
#
# This program is free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.


#------------------------- Configuration -------------------------#

# ChatGPT API key
API_KEY="<API_KEY>"
OPENAI_MODEL="<OPENAI_MODEL>" #for example gpt-4-turbo


# Set LOG_FILE path
LOG_FILE="logs/active-responses.log"

#------------------------- Gather parameters -------------------------#

# Extra arguments
read INPUT_JSON
YARA_PATH=$(echo $INPUT_JSON | jq -r .parameters.extra_args[1])
YARA_RULES=$(echo $INPUT_JSON | jq -r .parameters.extra_args[3])
FILENAME=$(echo $INPUT_JSON | jq -r .parameters.alert.syscheck.path)

size=0
actual_size=$(stat -c %s ${FILENAME})
while [ ${size} -ne ${actual_size} ]; do
    sleep 1
    size=${actual_size}
    actual_size=$(stat -c %s ${FILENAME})
done

#----------------------- Analyze parameters -----------------------#

if [[ ! $YARA_PATH ]] || [[ ! $YARA_RULES ]]
then
    echo "wazuh-YARA: ERROR - YARA active response error. YARA path and rules parameters are mandatory." >> ${LOG_FILE}
    exit 1
fi

#------------------------- Main workflow --------------------------#

# Execute YARA scan on the specified filename
YARA_output="$("${YARA_PATH}"/yara -w -r -m "$YARA_RULES" "$FILENAME")"

if [[ $YARA_output != "" ]]
then
    # Attempt to delete the file if any YARA rule matches
    if rm -rf "$FILENAME"; then
        echo "wazuh-YARA: INFO - Successfully deleted $FILENAME" >> ${LOG_FILE}
    else
        echo "wazuh-YARA: INFO - Unable to delete $FILENAME" >> ${LOG_FILE}
    fi

    # Flag to check if API key is invalid
    api_key_invalid=false

    # Iterate every detected rule
    while read -r line; do
        # Extract the description from the line using regex
        description=$(echo "$line" | grep -oP '(?<=description=").*?(?=")')
        if [[ $description != "" ]]; then
            # Prepare the message payload for ChatGPT
            payload=$(jq -n \
                --arg desc "$description" \
                --arg model "$OPENAI_MODEL" \
                '{
                    model: $model,
                    messages: [
                        {
                            role: "system",
                            content: "In one paragraph, tell me about the impact and how to mitigate \($desc)"
                        }
                    ],
                    temperature: 1,
                    max_tokens: 256,
                    top_p: 1,
                    frequency_penalty: 0,
                    presence_penalty: 0
                }')

            # Query ChatGPT for more information
            chatgpt_response=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $API_KEY" \
                -d "$payload")

            # Check for invalid API key error
            if echo "$chatgpt_response" | grep -q "invalid_request_error"; then
                api_key_invalid=true
                echo "wazuh-YARA: ERROR - Invalid ChatGPT API key" >> ${LOG_FILE}
                # Log Yara scan result without ChatGPT response
                echo "wazuh-YARA: INFO - Scan result: $line | chatgpt_response: none" >> ${LOG_FILE}
            else
                # Extract the response text from ChatGPT API response
                response_text=$(echo "$chatgpt_response" | jq -r '.choices[0].message.content')

                # Check if the response text is null and handle the error
                if [[ $response_text == "null" ]]; then
                    echo "wazuh-YARA: ERROR - ChatGPT API returned null response: $chatgpt_response" >> ${LOG_FILE}
                else
                    # Combine the YARA scan output and ChatGPT response
                    combined_output="wazuh-YARA: INFO - Scan result: $line | chatgpt_response: $response_text"

                    # Append the combined output to the log file
                    echo "$combined_output" >> ${LOG_FILE}
                fi
            fi
        else
            echo "wazuh-YARA: INFO - Scan result: $line" >> ${LOG_FILE}
        fi
    done <<< "$YARA_output"

    # If API key was invalid, log a specific message
    if $api_key_invalid; then
        echo "wazuh-YARA: INFO - API key is invalid. ChatGPT response omitted." >> ${LOG_FILE}
    fi
else
    echo "wazuh-YARA: INFO - No YARA rule matched." >> ${LOG_FILE}
fi

exit 0;
