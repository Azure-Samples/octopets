# Azure OIDC Setup Script using User-Assigned Managed Identity
# This script is perfect when you don't have permissions to create Service Principals

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$GitHubRepo,
    
    [Parameter(Mandatory=$false)]
    [string]$AzureLocation = "eastus2",
    
    [Parameter(Mandatory=$false)]
    [string]$IdentityName = "github-actions-identity"
)

Write-Host "🚀 Setting up OIDC with User-Assigned Managed Identity" -ForegroundColor Green
Write-Host "📋 Configuration:" -ForegroundColor Cyan
Write-Host "  Subscription: $SubscriptionId" -ForegroundColor White
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "  Managed Identity: $IdentityName" -ForegroundColor White
Write-Host "  GitHub Repository: $GitHubRepo" -ForegroundColor White
Write-Host "  Location: $AzureLocation" -ForegroundColor White

# Check if user is logged in to Azure
Write-Host "`n🔐 Checking Azure authentication..." -ForegroundColor Blue
$currentAccount = az account show --query "user.name" -o tsv 2>$null
if (-not $currentAccount) {
    Write-Host "❌ Please login to Azure CLI first: az login" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Logged in as: $currentAccount" -ForegroundColor Green

# Set subscription
Write-Host "🔧 Setting subscription..." -ForegroundColor Blue
az account set --subscription $SubscriptionId

# Check if resource group exists, create if not
Write-Host "🔧 Checking resource group..." -ForegroundColor Blue
$rgExists = az group exists --name $ResourceGroupName
if ($rgExists -eq "false") {
    Write-Host "📦 Creating resource group: $ResourceGroupName" -ForegroundColor Yellow
    az group create --name $ResourceGroupName --location $AzureLocation
    Write-Host "✅ Resource group created successfully!" -ForegroundColor Green
} else {
    Write-Host "✅ Resource group exists: $ResourceGroupName" -ForegroundColor Green
}

# Check if managed identity already exists
Write-Host "🔧 Checking if managed identity exists..." -ForegroundColor Blue
$existingIdentity = az identity show --resource-group $ResourceGroupName --name $IdentityName 2>$null
if ($existingIdentity) {
    Write-Host "⚠️ Managed identity '$IdentityName' already exists" -ForegroundColor Yellow

    # Ensure the output is valid JSON
    Write-Host "🔧 Debugging raw output before parsing..." -ForegroundColor Blue
    Write-Host "Raw output: $existingIdentity" -ForegroundColor White

    if (-not $existingIdentity) {
        Write-Host "❌ Invalid JSON output from az identity show" -ForegroundColor Red
        Write-Host "Raw output: $existingIdentity" -ForegroundColor White
        exit 1
    }

    $identity = $existingIdentity | ConvertFrom-Json
    $clientId = $identity.clientId
    $principalId = $identity.principalId

    # Validate extracted values
    if (-not $clientId -or -not $principalId) {
        Write-Host "❌ Failed to extract Client ID or Principal ID" -ForegroundColor Red
        Write-Host "Raw output: $existingIdentity" -ForegroundColor White
        exit 1
    }

    Write-Host "✅ Extracted Client ID: $clientId" -ForegroundColor Green
    Write-Host "✅ Extracted Principal ID: $principalId" -ForegroundColor Green
    Write-Host "✅ Using existing managed identity" -ForegroundColor Green
} else {
    # Create user-assigned managed identity
    Write-Host "🔧 Creating user-assigned managed identity..." -ForegroundColor Blue
    $identity = az identity create `
        --resource-group $ResourceGroupName `
        --name $IdentityName `
        --location $AzureLocation | ConvertFrom-Json

    Write-Host "✅ User-Assigned Managed Identity created successfully!" -ForegroundColor Green

    $clientId = $identity.clientId
    $principalId = $identity.principalId
}

Write-Host "  Client ID: $clientId" -ForegroundColor White
Write-Host "  Principal ID: $principalId" -ForegroundColor White

# Get tenant ID
$tenantId = az account show --query tenantId --output tsv

# Check current role assignments
Write-Host "🔧 Checking role assignments..." -ForegroundColor Blue
$existingRoles = az role assignment list --assignee $principalId --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" | ConvertFrom-Json

$hasContributor = $existingRoles | Where-Object { $_.roleDefinitionName -eq "Contributor" }

if (-not $hasContributor) {
    # Assign Contributor role to the managed identity
    Write-Host "🔧 Assigning Contributor role..." -ForegroundColor Blue
    az role assignment create `
        --assignee-object-id $principalId `
        --assignee-principal-type ServicePrincipal `
        --role "Contributor" `
        --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
    
    Write-Host "✅ Contributor role assigned successfully!" -ForegroundColor Green
} else {
    Write-Host "✅ Contributor role already assigned" -ForegroundColor Green
}

# List existing federated credentials
Write-Host "🔧 Checking existing federated credentials..." -ForegroundColor Blue
$existingCreds = az identity federated-credential list --identity-name $IdentityName --resource-group $ResourceGroupName | ConvertFrom-Json

$mainBranchCred = $existingCreds | Where-Object { $_.subject -eq "repo:${GitHubRepo}:ref:refs/heads/main" }
$prCred = $existingCreds | Where-Object { $_.subject -eq "repo:${GitHubRepo}:pull_request" }

# Create federated credential for main branch
if (-not $mainBranchCred) {
    Write-Host "🔧 Creating federated credential for main branch..." -ForegroundColor Blue
    az identity federated-credential create `
        --name "github-main" `
        --identity-name $IdentityName `
        --resource-group $ResourceGroupName `
        --issuer "https://token.actions.githubusercontent.com" `
        --subject "repo:${GitHubRepo}:ref:refs/heads/main" `
        --audiences "api://AzureADTokenExchange"
    
    Write-Host "✅ Main branch federated credential created!" -ForegroundColor Green
} else {
    Write-Host "✅ Main branch federated credential already exists" -ForegroundColor Green
}

# Create federated credential for pull requests
if (-not $prCred) {
    Write-Host "🔧 Creating federated credential for pull requests..." -ForegroundColor Blue
    az identity federated-credential create `
        --name "github-pr" `
        --identity-name $IdentityName `
        --resource-group $ResourceGroupName `
        --issuer "https://token.actions.githubusercontent.com" `
        --subject "repo:${GitHubRepo}:pull_request" `
        --audiences "api://AzureADTokenExchange"
    
    Write-Host "✅ Pull request federated credential created!" -ForegroundColor Green
} else {
    Write-Host "✅ Pull request federated credential already exists" -ForegroundColor Green
}

Write-Host "`n🎉 OIDC setup completed successfully!" -ForegroundColor Green

# Display GitHub secrets to set
Write-Host "`n📋 GitHub Secrets to Configure:" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host "AZURE_CLIENT_ID: $clientId" -ForegroundColor White
Write-Host "AZURE_TENANT_ID: $tenantId" -ForegroundColor White
Write-Host "AZURE_SUBSCRIPTION_ID: $SubscriptionId" -ForegroundColor White

Write-Host "`n📋 GitHub Variables to Configure:" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "AZURE_ENV_NAME: dev (or your preferred environment name)" -ForegroundColor White
Write-Host "AZURE_LOCATION: $AzureLocation" -ForegroundColor White

Write-Host "`n🔗 Setup Instructions:" -ForegroundColor Magenta
Write-Host "1. Go to your GitHub repository: https://github.com/$GitHubRepo" -ForegroundColor White
Write-Host "2. Navigate to Settings > Secrets and variables > Actions" -ForegroundColor White
Write-Host "3. Click 'New repository secret' and add each secret above" -ForegroundColor White
Write-Host "4. Click the 'Variables' tab and add each variable above" -ForegroundColor White
Write-Host "5. Commit and push your .github/workflows/*.yml files" -ForegroundColor White
Write-Host "6. Test by creating a pull request or pushing to main branch" -ForegroundColor White

Write-Host "`n🛡️ Security Benefits of Managed Identity:" -ForegroundColor Green
Write-Host "✅ No secrets to manage or rotate" -ForegroundColor White
Write-Host "✅ Azure-managed lifecycle" -ForegroundColor White
Write-Host "✅ Integrated with Azure RBAC" -ForegroundColor White
Write-Host "✅ Short-lived tokens only" -ForegroundColor White

Write-Host "`n💡 Pro Tips:" -ForegroundColor Cyan
Write-Host "• Use validate-oidc.ps1 to verify your setup" -ForegroundColor White
Write-Host "• Consider different managed identities for dev/staging/prod" -ForegroundColor White
Write-Host "• The managed identity is scoped to your resource group only" -ForegroundColor White

Write-Host "`n🔍 Troubleshooting:" -ForegroundColor Yellow
Write-Host "If you get permission errors, ensure you have:" -ForegroundColor White
Write-Host "• 'Managed Identity Contributor' role in the subscription/RG" -ForegroundColor White
Write-Host "• 'User Access Administrator' role to assign roles" -ForegroundColor White
Write-Host "• Or ask an admin to run this script for you" -ForegroundColor White
