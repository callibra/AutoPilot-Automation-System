############################## Professional PS2EXE builder - DASHBOARD #######################################################
$inputScript = "C:\Users\ASUS\Desktop\Dashboard.ps1"
$outputExe   = "C:\Users\ASUS\Desktop\AutoPilot.exe"
$iconFile    = "C:\Users\ASUS\Desktop\autopilot.ico"

# Ensure PS2EXE is installed
if (-not (Get-Module -ListAvailable -Name PS2EXE)) {
    Write-Host "Installing PS2EXE module..."
    Install-Module -Name PS2EXE -Scope CurrentUser -Force
}

try {
    Write-Host "Building AutoPilot Dashboard EXE..."

    Invoke-PS2EXE `
        -InputFile     $inputScript `
        -OutputFile    $outputExe `
        -IconFile      $iconFile `
        -NoConsole `
        -RequireAdmin `
        -STA `
        -Title         "AutoPilot Dashboard" `
        -Description   "AutoPilot Control Panel" `
        -Product       "AutoPilot" `
        -Company       "Callibra" `
        -Version       "1.0.0"

    Write-Host "========================================="
    Write-Host " BUILD SUCCESSFUL"
    Write-Host "EXE Location:"
    Write-Host " $outputExe"
    Write-Host "========================================="
}
catch {
    Write-Error " Build failed:"
    Write-Error $_
    exit 1
}

# <<< THIS keeps the console open >>>
Write-Host "`nPress ENTER to close this window..."
Read-Host

# Install-Module ps2exe -Scope CurrentUser  - instal this first
# Install-Module -Name PS2EXE -Force   - or this 

<######################################   SCHORTCUT VBS FILE   #############################################

' ===========================
' Dashboard GUI Launcher (ADMIN + FLAG)
' ===========================

Set shellApp = CreateObject("Shell.Application")
Set fso = CreateObject("Scripting.FileSystemObject")

' Flag paths
flagFolder = "C:\AutoPilot\Autopilot_Data"
flagFile   = flagFolder & "\Dashboard.flag"

' Kreiraj folder ako ne postoi
If Not fso.FolderExists(flagFolder) Then
    fso.CreateFolder flagFolder
End If

' Kreiraj / overwrite flag fajl
Set flag = fso.CreateTextFile(flagFile, True)
flag.WriteLine "Dashboard started: " & Now
flag.Close

' Start Dashboard so admin prava
shellApp.ShellExecute _
    "powershell.exe", _
    "-NoProfile -ExecutionPolicy Bypass -File ""C:\AutoPilot\Dashboard.ps1""", _
    "", _
    "runas", _
    0

#>