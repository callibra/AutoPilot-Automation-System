############################## Professional PS2EXE builder - DASHBOARD #######################################################
$ErrorActionPreference = 'Stop'

$inputScript = "C:\Users\ASUS\Desktop\Dashboard.ps1"
$outputExe   = "C:\Users\ASUS\Desktop\AutoPilot.exe"
$iconFile    = "C:\Users\ASUS\Desktop\autopilot.ico"

try {
    foreach ($f in @($inputScript, $iconFile)) {
        if (-not (Test-Path $f)) { throw "Missing file: $f" }
    }

    if (-not (Get-Module -ListAvailable -Name PS2EXE)) {
        Write-Host "Installing PS2EXE module..."
        Install-Module -Name PS2EXE -Repository PSGallery -Scope CurrentUser -Force
    }
    Import-Module PS2EXE

    if (Test-Path $outputExe) { Remove-Item $outputExe -Force }

    Write-Host "Building Data EXE..."

    Invoke-PS2EXE `
        -InputFile   $inputScript `
        -OutputFile  $outputExe `
        -IconFile    $iconFile `
        -NoConsole `
        -NoOutput `
        -NoError `
        -RequireAdmin `
        -STA `
        -x64 `
        -DPIAware `
        -Title       "AutoPilot Automation System" `
        -Description "AutoPilot Dashboard" `
        -Product     "Dashboard" `
        -Company     "Callibra" `
        -Copyright   "(c) Callibra" `
        -Version     "1.0.3.0"

    if (-not (Test-Path $outputExe)) { throw "EXE was not created." }

    # Optional: sign the exe (needs a real code-signing certificate)
    # $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1
    # Set-AuthenticodeSignature -FilePath $outputExe -Certificate $cert `
    #     -TimestampServer "http://timestamp.digicert.com" | Out-Null

    Write-Host "========================================="
    Write-Host " BUILD SUCCESSFUL"
    Write-Host " $outputExe"
    Write-Host "========================================="
}
catch {
    Write-Host " Build failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`nPress ENTER to close this window..."
Read-Host

############################## Professional PS2EXE builder - DASHBOARD #######################################################