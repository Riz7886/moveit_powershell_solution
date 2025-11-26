
# MOVEIT SSL AUTO-FIX SCRIPT...
param(
    [string]$Domain = "moveit.pyxhealth.com",
    [string]$PfxFolder = "C:\Users\$env:USERNAME\Downloads\DMZ"
)

function Write-Info($msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-OK($msg){ Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-ERR($msg){ Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Host "`n=== MOVEIT SSL AUTO-FIX STARTED ===" -ForegroundColor Yellow

$PfxFile = Get-ChildItem -Path $PfxFolder -Filter *.pfx -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (!$PfxFile) {
    Write-ERR "NO PFX FOUND in $PfxFolder"
    exit
}
Write-OK "Detected certificate: $($PfxFile.FullName)"

try {
    $CertPassword = Read-Host -Prompt "Enter PFX password"
    $Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
    $Cert.Import($PfxFile.FullName, $CertPassword, "Exportable,PersistKeySet")
    Write-OK "Certificate loaded successfully"
}
catch {
    Write-ERR "Certificate import FAILED: $($_.Exception.Message)"
    exit
}

Write-Info "Enabling TLS 1.2"
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

try {
    Write-Info "Testing HTTPS handshake..."
    $result = Invoke-WebRequest -Uri "https://$Domain" -UseBasicParsing -ErrorAction Stop
    Write-OK "HTTPS handshake successful."
}
catch {
    Write-ERR "HTTPS handshake FAILED. Fixing trust..."
    try {
        Write-Info "Installing cert in LocalMachine\My"
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My","LocalMachine")
        $store.Open("ReadWrite")
        $store.Add($Cert)
        $store.Close()
        Write-OK "Certificate installed. Retest HTTPS."
    }
    catch {
        Write-ERR "Cert install failed: $($_.Exception.Message)"
        exit
    }
}

Write-OK "MOVEIT SSL FIX COMPLETE"
