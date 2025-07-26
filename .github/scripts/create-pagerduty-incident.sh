#!/bin/zsh

# This script creates a PagerDuty incident for a Container App using the PagerDuty API
# Parameters (all optional with defaults):
# $1 - Container App Resource Name (defaults to "octopetsapi")
# $2 - PagerDuty Service Name (defaults to "Default Service")
# $3 - PagerDuty Urgency (defaults to "high")
#
# Environment variables required:
# PAGERDUTY_API_TOKEN - PagerDuty API token with appropriate permissions
# PAGERDUTY_SERVICE_ID - PagerDuty Service ID
# PAGERDUTY_PRIORITY_ID - PagerDuty Priority ID (optional, defaults to P28K36R for P1)
#
# Usage examples:
# ./create-pagerduty-incident.sh                # Use all defaults
# ./create-pagerduty-incident.sh myapp          # Custom app name, defaults for the rest
# ./create-pagerduty-incident.sh "" "My Service"   # Default app name, custom service name

# Check if PAGERDUTY_API_TOKEN is set
if [ -z "$PAGERDUTY_API_TOKEN" ]; then
    echo "Error: PAGERDUTY_API_TOKEN environment variable is not set"
    echo "Please set it with: export PAGERDUTY_API_TOKEN=your-api-token"
    exit 1
fi

# Check if PAGERDUTY_SERVICE_ID is set
if [ -z "$PAGERDUTY_SERVICE_ID" ]; then
    echo "Error: PAGERDUTY_SERVICE_ID environment variable is not set"
    echo "Please set it with: export PAGERDUTY_SERVICE_ID=your-service-id"
    exit 1
fi

# Check if PAGERDUTY_PRIORITY_ID is set (optional, defaults to P1)
PAGERDUTY_PRIORITY_ID=${PAGERDUTY_PRIORITY_ID:-"P28K36R"}

# Set parameters with defaults
CONTAINER_APP_NAME=${1:-"octopetsapi"}
PAGERDUTY_SERVICE_NAME=${2:-"Default Service"}
PAGERDUTY_URGENCY=${4:-"high"}

# Display parameter info
echo "Using the following parameters:"
echo "Container App: $CONTAINER_APP_NAME"
echo "PagerDuty Service Name: $PAGERDUTY_SERVICE_NAME"
echo "PagerDuty Service ID: $PAGERDUTY_SERVICE_ID"
echo "PagerDuty Priority ID: $PAGERDUTY_PRIORITY_ID"
echo "PagerDuty Urgency: $PAGERDUTY_URGENCY"

# Set the incident title with timestamp
TIMESTAMP=$(date +"%Y%m%d-%H%M")
INCIDENT_TITLE="Container App $CONTAINER_APP_NAME is down with 500 errors [$TIMESTAMP]"

# Get the description from the prompt file
# Go up one directory if running from within .github/scripts
REPO_ROOT="$(dirname "$(dirname "$PWD")")"
if [[ "$PWD" == *".github/scripts" ]]; then
    PROMPT_PATH="$REPO_ROOT/.github/prompts/sreagent-500errors.prompt.md"
else
    # If running from repo root
    PROMPT_PATH="$PWD/.github/prompts/sreagent-500errors.prompt.md"
fi

if [ ! -f "$PROMPT_PATH" ]; then
    echo "Error: Prompt file not found at $PROMPT_PATH"
    exit 1
fi

INCIDENT_DESCRIPTION=$(cat "$PROMPT_PATH")

# Generate a unique deduplication key
DEDUP_KEY="octopets-incident-$(date +%s)-$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | fold -w 6 | head -n 1)"

# Create JSON payload for the PagerDuty API
JSON_PAYLOAD=$(cat <<EOF
{
  "incident": {
    "type": "incident",
    "title": "$INCIDENT_TITLE",
    "service": {
      "id": "$PAGERDUTY_SERVICE_ID",
      "type": "service_reference"
    },
    "urgency": "$PAGERDUTY_URGENCY",
    "priority": {
      "id": "$PAGERDUTY_PRIORITY_ID",
      "type": "priority_reference"
    },
    "body": {
      "type": "incident_body",
      "details": "$INCIDENT_DESCRIPTION"
    },
    "incident_key": "$DEDUP_KEY"
  }
}
EOF
)

# Create the incident using the PagerDuty API
echo "Creating PagerDuty incident..."
RESPONSE=$(curl -s -X POST \
  --header "Content-Type: application/json" \
  --header "Accept: application/vnd.pagerduty+json;version=2" \
  --header "Authorization: Token token=$PAGERDUTY_API_TOKEN" \
  --data "$JSON_PAYLOAD" \
  "https://api.pagerduty.com/incidents")

# Print the full API response for debugging
echo "API Response: $RESPONSE"

# Check if the request was successful
if echo "$RESPONSE" | grep -q "id"; then
    INCIDENT_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
    INCIDENT_NUMBER=$(echo "$RESPONSE" | grep -o '"incident_number":[0-9]*' | cut -d':' -f2)
    
    echo "PagerDuty incident created successfully!"
    echo "Incident ID: $INCIDENT_ID"
    echo "Incident Number: $INCIDENT_NUMBER"
    echo "Incident Title: $INCIDENT_TITLE"
    echo "Service Name: $PAGERDUTY_SERVICE_NAME"
else
    echo "Error creating PagerDuty incident:"
    echo "$RESPONSE"
    exit 1
fi
