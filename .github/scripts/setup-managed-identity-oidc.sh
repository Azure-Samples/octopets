#!/bin/bash

# Azure OIDC Setup Script using User-Assigned Managed Identity (Bash version)
# This script is perfect when you don't have permissions to create Service Principals

set -e  # Exit on any error

# Function to print colored output
print_status() {
    echo -e "\033[32m✅ $1\033[0m"
}

print_info() {
    echo -e "\033[34m🔧 $1\033[0m"
}

print_error() {
    echo -e "\033[31m❌ $1\033[0m"
}

print_warning() {
    echo -e "\033[33m⚠️ $1\033[0m"
}

print_header() {
    echo -e "\033[36m$1\033[0m"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Required Options:"
    echo "  -s, --subscription-id SUBSCRIPTION_ID    Azure subscription ID"
    echo "  -g, --resource-group RESOURCE_GROUP      Resource group name"
    echo "  -r, --github-repo GITHUB_REPO           GitHub repository (format: owner/repo)"
    echo ""
    echo "Optional Options:"
    echo "  -l, --location LOCATION                  Azure location (default: eastus2)"
    echo "  -i, --identity-name IDENTITY_NAME        Managed identity name (default: github-actions-identity)"
    echo "  -h, --help                              Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 -s 'your-subscription-id' -g 'rg-recipe-app' -r 'username/repo-name'"
}

# Parse command line arguments
SUBSCRIPTION_ID=""
RESOURCE_GROUP_NAME=""
GITHUB_REPO=""
AZURE_LOCATION="eastus2"
IDENTITY_NAME="github-actions-identity"

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--subscription-id)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP_NAME="$2"
            shift 2
            ;;
        -r|--github-repo)
            GITHUB_REPO="$2"
            shift 2
            ;;
        -l|--location)
            AZURE_LOCATION="$2"
            shift 2
            ;;
        -i|--identity-name)
            IDENTITY_NAME="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$SUBSCRIPTION_ID" || -z "$RESOURCE_GROUP_NAME" || -z "$GITHUB_REPO" ]]; then
    print_error "Missing required parameters"
    show_usage
    exit 1
fi

print_header "🚀 Setting up OIDC with User-Assigned Managed Identity"
print_header "📋 Configuration:"
echo "  Subscription: $SUBSCRIPTION_ID"
echo "  Resource Group: $RESOURCE_GROUP_NAME"
echo "  Managed Identity: $IDENTITY_NAME"
echo "  GitHub Repository: $GITHUB_REPO"
echo "  Location: $AZURE_LOCATION"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first:"
    echo "  https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in to Azure
print_info "Checking Azure authentication..."
if ! CURRENT_ACCOUNT=$(az account show --query "user.name" -o tsv 2>/dev/null); then
    print_error "Please login to Azure CLI first: az login"
    exit 1
fi

print_status "Logged in as: $CURRENT_ACCOUNT"

# Set subscription
print_info "Setting subscription..."
az account set --subscription "$SUBSCRIPTION_ID"

# Check if resource group exists, create if not
print_info "Checking resource group..."
if az group exists --name "$RESOURCE_GROUP_NAME" | grep -q "false"; then
    print_warning "Creating resource group: $RESOURCE_GROUP_NAME"
    az group create --name "$RESOURCE_GROUP_NAME" --location "$AZURE_LOCATION"
    print_status "Resource group created successfully!"
else
    print_status "Resource group exists: $RESOURCE_GROUP_NAME"
fi

# Check if managed identity already exists
print_info "Checking if managed identity exists..."
if EXISTING_IDENTITY=$(az identity show --resource-group "$RESOURCE_GROUP_NAME" --name "$IDENTITY_NAME" --output json 2>/dev/null); then
    print_warning "Managed identity '$IDENTITY_NAME' already exists"
    print_status "Using existing managed identity"

    # Debug: Print raw output before parsing
    print_info "Debugging raw output before parsing..."
    echo "Raw output: $EXISTING_IDENTITY"

    # Ensure the output is valid JSON
    if ! echo "$EXISTING_IDENTITY" | jq empty; then
        print_error "Invalid JSON output from az identity show"
        echo "Raw output: $EXISTING_IDENTITY"

        # Fallback parsing if jq fails
        CLIENT_ID=$(echo "$EXISTING_IDENTITY" | grep -o '"clientId":"[^"]*' | cut -d'"' -f4)
        PRINCIPAL_ID=$(echo "$EXISTING_IDENTITY" | grep -o '"principalId":"[^"]*' | cut -d'"' -f4)
    else
        CLIENT_ID=$(echo "$EXISTING_IDENTITY" | jq -r '.clientId')
        PRINCIPAL_ID=$(echo "$EXISTING_IDENTITY" | jq -r '.principalId')
    fi

    # Debug: Print extracted values after parsing
    print_info "Debugging extracted values..."
    echo "Extracted Client ID: $CLIENT_ID"
    echo "Extracted Principal ID: $PRINCIPAL_ID"

    # Validate extracted values
    if [[ -z "$CLIENT_ID" || -z "$PRINCIPAL_ID" ]]; then
        print_error "Failed to extract Client ID or Principal ID"
        echo "Raw output: $EXISTING_IDENTITY"
        exit 1
    fi
else
    # Create user-assigned managed identity
    print_info "Creating user-assigned managed identity..."
    IDENTITY_JSON=$(az identity create \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name "$IDENTITY_NAME" \
        --location "$AZURE_LOCATION" \
        --output json)

    # Debug: Print raw output
    echo "Raw output of az identity create: $IDENTITY_JSON"

    # Ensure the output is valid JSON
    if ! echo "$IDENTITY_JSON" | jq empty; then
        print_error "Invalid JSON output from az identity create"
        echo "Raw output: $IDENTITY_JSON"
        exit 1
    fi

    CLIENT_ID=$(echo "$IDENTITY_JSON" | jq -r '.clientId')
    PRINCIPAL_ID=$(echo "$IDENTITY_JSON" | jq -r '.principalId')

    print_status "User-Assigned Managed Identity created successfully!"
fi

# Debug: Print extracted values
print_info "Using extracted values for Client ID and Principal ID"
echo "Client ID: $CLIENT_ID"
echo "Principal ID: $PRINCIPAL_ID"

# Get tenant ID
TENANT_ID=$(az account show --query tenantId --output tsv)

# Check current role assignments
print_info "Checking role assignments..."
EXISTING_ROLES=$(az role assignment list --assignee "$PRINCIPAL_ID" --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME")

if echo "$EXISTING_ROLES" | jq -e '.[] | select(.roleDefinitionName == "Contributor")' > /dev/null; then
    print_status "Contributor role already assigned"
else
    # Assign Contributor role to the managed identity
    print_info "Assigning Contributor role..."
    az role assignment create \
        --assignee-object-id "$PRINCIPAL_ID" \
        --assignee-principal-type ServicePrincipal \
        --role "Contributor" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME"
    
    print_status "Contributor role assigned successfully!"
fi

# List existing federated credentials
print_info "Checking existing federated credentials..."
EXISTING_CREDS=$(az identity federated-credential list --identity-name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP_NAME")

# Check for main branch credential
if echo "$EXISTING_CREDS" | jq -e ".[] | select(.subject == \"repo:${GITHUB_REPO}:ref:refs/heads/main\")" > /dev/null; then
    print_status "Main branch federated credential already exists"
else
    # Create federated credential for main branch
    print_info "Creating federated credential for main branch..."
    az identity federated-credential create \
        --name "github-main" \
        --identity-name "$IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --issuer "https://token.actions.githubusercontent.com" \
        --subject "repo:${GITHUB_REPO}:ref:refs/heads/main" \
        --audiences "api://AzureADTokenExchange"
    
    print_status "Main branch federated credential created!"
fi

# Check for pull request credential
if echo "$EXISTING_CREDS" | jq -e ".[] | select(.subject == \"repo:${GITHUB_REPO}:pull_request\")" > /dev/null; then
    print_status "Pull request federated credential already exists"
else
    # Create federated credential for pull requests
    print_info "Creating federated credential for pull requests..."
    az identity federated-credential create \
        --name "github-pr" \
        --identity-name "$IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --issuer "https://token.actions.githubusercontent.com" \
        --subject "repo:${GITHUB_REPO}:pull_request" \
        --audiences "api://AzureADTokenExchange"
    
    print_status "Pull request federated credential created!"
fi

print_header "🎉 OIDC setup completed successfully!"

# Display GitHub secrets to set
print_header ""
print_header "📋 GitHub Secrets to Configure:"
print_header "================================"
echo "AZURE_CLIENT_ID: $CLIENT_ID"
echo "AZURE_TENANT_ID: $TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"

print_header ""
print_header "📋 GitHub Variables to Configure:"
print_header "=================================="
echo "AZURE_ENV_NAME: dev (or your preferred environment name)"
echo "AZURE_LOCATION: $AZURE_LOCATION"

print_header ""
print_header "🔗 Setup Instructions:"
echo "1. Go to your GitHub repository: https://github.com/$GITHUB_REPO"
echo "2. Navigate to Settings > Secrets and variables > Actions"
echo "3. Click 'New repository secret' and add each secret above"
echo "4. Click the 'Variables' tab and add each variable above"
echo "5. Commit and push your .github/workflows/*.yml files"
echo "6. Test by creating a pull request or pushing to main branch"

print_header ""
print_header "🛡️ Security Benefits of Managed Identity:"
print_status "No secrets to manage or rotate"
print_status "Azure-managed lifecycle"
print_status "Integrated with Azure RBAC"
print_status "Short-lived tokens only"

print_header ""
print_header "💡 Pro Tips:"
echo "• Use validate-oidc.sh to verify your setup"
echo "• Consider different managed identities for dev/staging/prod"
echo "• The managed identity is scoped to your resource group only"

print_header ""
print_header "🔍 Troubleshooting:"
echo "If you get permission errors, ensure you have:"
echo "• 'Managed Identity Contributor' role in the subscription/RG"
echo "• 'User Access Administrator' role to assign roles"
echo "• Or ask an admin to run this script for you"
