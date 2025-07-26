#!/bin/zsh

# This script creates an Azure Monitor alert rule for a Container App
# Parameters (all optional with defaults):
# $1 - Resource Group Name (defaults to "rg_octopets")
# $2 - Container App Resource Name (defaults to "octopetsapi")
# $3 - App Insights Resource Name (defaults to "octopets_appinsights-abc123xyz456")
# $4 - Subscription ID (defaults to "12345678-abcd-9e8f-7g6h-5i4j3k2l1m0n")
# $5 - Location (defaults to "eastus")
#
# Usage examples:
# ./create-appinsights.sh                     # Use all defaults
# ./create-appinsights.sh my-resource-group   # Custom resource group, defaults for the rest
# ./create-appinsights.sh "" myapp myinsights # Default resource group, custom app and insights
# ./create-appinsights.sh "" "" "" "12345678-abcd-9e8f-7g6h-5i4j3k2l1m0n" # Custom subscription

# Set parameters with defaults
RESOURCE_GROUP=${1:-"rg-octopets"}
CONTAINER_APP_NAME=${2:-"octopetsapi"}
APP_INSIGHTS_NAME=${3:-"octopets_appinsights-abcd123xyz456"}
SUBSCRIPTION_ID=${4:-"12345678-abcd-9e8f-7g6h-5i4j3k2l1m0n"}
LOCATION=${5:-"eastus"}

# Display parameter info
echo "Using the following parameters:"
echo "Resource Group: $RESOURCE_GROUP"
echo "Container App: $CONTAINER_APP_NAME"
echo "App Insights: $APP_INSIGHTS_NAME"
echo "Subscription: $SUBSCRIPTION_ID"
echo "Location: $LOCATION"

# Generate a unique suffix for the alert name
SUFFIX=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | fold -w 6 | head -n 1)
ALERT_NAME="octopets-failed-requests-alert-${SUFFIX}"
ACTION_GROUP_NAME="octopets-action-group-${SUFFIX}"

# If subscription ID is provided, set it
if [ -n "$SUBSCRIPTION_ID" ]; then
    echo "Setting subscription to $SUBSCRIPTION_ID"
    az account set --subscription $SUBSCRIPTION_ID
fi

# Get the resource IDs
echo "Getting Container App resource ID..."
CONTAINER_APP_ID=$(az containerapp show \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINER_APP_NAME \
    --query id -o tsv)

if [ -z "$CONTAINER_APP_ID" ]; then
    echo "Error: Container App '$CONTAINER_APP_NAME' not found in resource group '$RESOURCE_GROUP'"
    exit 1
fi

echo "Getting App Insights resource ID..."
APP_INSIGHTS_ID=$(az monitor app-insights component show \
    --app $APP_INSIGHTS_NAME \
    --resource-group $RESOURCE_GROUP \
    --query id -o tsv)

if [ -z "$APP_INSIGHTS_ID" ]; then
    echo "Error: App Insights '$APP_INSIGHTS_NAME' not found in resource group '$RESOURCE_GROUP'"
    exit 1
fi

# Create action group for the alert (where notifications will be sent)
echo "Creating action group: $ACTION_GROUP_NAME"
az monitor action-group create \
    --resource-group $RESOURCE_GROUP \
    --name $ACTION_GROUP_NAME \
    --short-name "OctopetsAG" \
    --location $LOCATION

# Get the action group ID
ACTION_GROUP_ID=$(az monitor action-group show \
    --resource-group $RESOURCE_GROUP \
    --name $ACTION_GROUP_NAME \
    --query id -o tsv)

# Create the alert rule
echo "Creating alert rule: $ALERT_NAME"
az monitor metrics alert create \
    --resource-group $RESOURCE_GROUP \
    --name $ALERT_NAME \
    --scopes $APP_INSIGHTS_ID \
    --condition "count requests/failed > 0" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --action $ACTION_GROUP_ID \
    --description "$(cat "$PWD/.github/prompts/sreagent.prompt.md")" \
    --severity 0

echo "Alert rule creation completed."
echo "Alert Name: $ALERT_NAME"
echo "Container App: $CONTAINER_APP_NAME"
echo "Action Group: $ACTION_GROUP_NAME"
echo "Resource Group: $RESOURCE_GROUP"
