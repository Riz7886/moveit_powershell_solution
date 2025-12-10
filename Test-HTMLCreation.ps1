#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test HTML File Creation - Troubleshooting Script
.DESCRIPTION
    Simple test to verify HTML files can be created and opened.
    If this works, the main audit script should work too.
#>

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TESTING HTML FILE CREATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Get Downloads folder
$downloadsPath = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$testFile = Join-Path $downloadsPath "Test-HTML-$timestamp.html"

Write-Host "`nDownloads folder: $downloadsPath" -ForegroundColor Yellow
Write-Host "Test file path: $testFile" -ForegroundColor Yellow

# Create simple HTML
$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Test HTML File</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 50px;
            text-align: center;
        }
        .box {
            background: white;
            color: #333;
            padding: 40px;
            border-radius: 10px;
            max-width: 600px;
            margin: 0 auto;
        }
        h1 { color: #667eea; }
        .success { color: #10b981; font-size: 48px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="box">
        <div class="success">✓</div>
        <h1>SUCCESS!</h1>
        <h2>HTML File Creation Works!</h2>
        <p>This test file was created at: $(Get-Date -Format "MMMM dd, yyyy HH:mm:ss")</p>
        <p>File location: <code>$testFile</code></p>
        <hr>
        <p><strong>If you can see this, your audit script should work too!</strong></p>
    </div>
</body>
</html>
"@

# Try to write file
try {
    Write-Host "`nAttempting to create HTML file..." -ForegroundColor Cyan
    [System.IO.File]::WriteAllText($testFile, $html, [System.Text.UTF8Encoding]::new($false))
    
    Write-Host "✓ File created successfully!" -ForegroundColor Green
    Write-Host "✓ File location: $testFile" -ForegroundColor Green
    
    # Check if file exists
    if (Test-Path $testFile) {
        $fileSize = (Get-Item $testFile).Length
        Write-Host "✓ File exists! Size: $fileSize bytes" -ForegroundColor Green
    } else {
        Write-Host "✗ ERROR: File was not created!" -ForegroundColor Red
        exit 1
    }
    
    # Try to open in browser
    Write-Host "`nAttempting to open file in browser..." -ForegroundColor Cyan
    Start-Process $testFile
    Write-Host "✓ File opened in browser!" -ForegroundColor Green
    
} catch {
    Write-Host "✗ ERROR creating file: $_" -ForegroundColor Red
    Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Check if Downloads folder exists" -ForegroundColor Yellow
    Write-Host "2. Check file permissions" -ForegroundColor Yellow
    Write-Host "3. Try running PowerShell as Administrator" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "TEST COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "`nYour audit script should work fine now." -ForegroundColor Cyan
Write-Host "The HTML file should have opened in your browser." -ForegroundColor Cyan
