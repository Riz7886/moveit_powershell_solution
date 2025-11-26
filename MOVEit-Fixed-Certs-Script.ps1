
# MOVEIT FRONTDOOR + KEYVAULT + CERT AUTO-FIX SCRIPT (FIXED VERSION)

function Write-Log {
    param([string]$Message,[string]$Color="White")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $Message" -ForegroundColor $Color
}

$ResourceGroup = "rg-networking"
$KeyVaultName  = "kv-moveit-cert-prod"
$Location      = "westus"
$PfxPath       = "C:\\Users\\SyedRizvi\\Downloads\\DMZ\\moveit.pfx"
$PfxPassword   = "CHANGE_ME"

if (-not (Test-Path $PfxPath)) { Write-Log "ERROR: Missing PFX file at $PfxPath" Red; exit }

$login = az account show 2>$null
if (-not $login) { az login --use-device-code | Out-Null }

$rg = az group show --name $ResourceGroup 2>$null
if (-not $rg) {
    az group create --name $ResourceGroup --location $Location --output none
}

$kv = az keyvault show --name $KeyVaultName --resource-group $ResourceGroup 2>$null
if (-not $kv) {
    az keyvault create `
        --name $KeyVaultName `
        --resource-group $ResourceGroup `
        --location $Location `
        --enable-soft-delete true `
        --enable-purge-protection false `
        --sku standard `
        --output none
}

az keyvault certificate import `
    --vault-name $KeyVaultName `
    --name "moveit-cert" `
    --file $PfxPath `
    --password $PfxPassword `
    --output none

Write-Log "Certificate imported successfully." Green
