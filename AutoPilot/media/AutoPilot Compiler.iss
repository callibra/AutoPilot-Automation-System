; ===================================================
; AutoPilot Installer - Full Version
; ===================================================

[Setup]
AppName=Autopilot Automation System
AppVersion=1.0.3.0
DefaultDirName=C:\AutoPilot
DefaultGroupName=AutoPilot
OutputBaseFilename=AutoPilot_SetUp
Compression=lzma
SolidCompression=yes
WizardStyle=classic
PrivilegesRequired=admin
UninstallFilesDir={app}
DisableDirPage=no
SetupIconFile=AutoPilot\media\autopilot.ico
WizardSmallImageFile=AutoPilot\media\autopilot.bmp
WizardSmallImageBackColor=none
WizardImageAlphaFormat=defined
UninstallDisplayIcon={app}\AutoPilot.exe

[Messages]
BeveledLabel=AutoPilot Automation System

[Files]
; Main application files – exclude runtime data folders
Source: "AutoPilot\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion; Excludes: Autopilot_Data\*,Data\*,Camera\*,JSON\*

; JSON folder – copy only if JSON folder не постои (fresh install)
Source: "AutoPilot\JSON\*"; DestDir: "{app}\JSON"; Flags: recursesubdirs ignoreversion onlyifdoesntexist

; Embed PawnIO setup for silent installation during AutoPilot setup.
Source: "AutoPilot\installers\PawnIO_setup.exe"; DestName: "PawnIO_setup.exe"; Flags: dontcopy

; Keep a copy with AutoPilot so the same PawnIO package can silently uninstall it.
Source: "AutoPilot\installers\PawnIO_setup.exe"; DestDir: "{app}"; DestName: "PawnIO_setup.exe"; Flags: ignoreversion

; Embed the setup-page logo.
Source: "AutoPilot\media\autopilot.bmp"; Flags: dontcopy

[Icons]
Name: "{commondesktop}\AutoPilot"; Filename: "{app}\AutoPilot.exe"; WorkingDir: "{app}"
Name: "{group}\Uninstall AutoPilot"; Filename: "{uninstallexe}"

[Tasks]
Name: "launchapp"; Description: "Launch AutoPilot after closing Setup"

[UninstallRun]
Filename: "{win}\System32\WindowsPowerShell\v1.0\powershell.exe"; \
Parameters: "-Command Remove-ItemProperty -Path 'HKCU:\Software\MicrosoftKeySecurity' -Name 'ProgramValueKey' -ErrorAction SilentlyContinue"; \
Flags: runhidden; \
RunOnceId: "RemoveRegistryKey"

Filename: "{cmd}"; \
Parameters: "/C rd /s /q ""%USERPROFILE%\AppVerifierLogs"""; \
Flags: runhidden; \
RunOnceId: "DeleteAppVerifierLogs"

[Code]
var
  ResultCode: Integer;
  SetupFinished: Boolean;
  LogMemo: TNewMemo;
  DetailsButton: TNewButton;
  DetailsVisible: Boolean;
  LastStatus: string;
  LastFile: string;

function SendMessageW(hWnd: HWND; Msg: UINT; wParam: Longint; lParam: Longint): Longint;
  external 'SendMessageW@user32.dll stdcall';

procedure AddLog(const S: string);
begin
  if LogMemo = nil then
    Exit;
  LogMemo.Lines.Add(S);
  SendMessageW(LogMemo.Handle, $00B6, 0, LogMemo.Lines.Count);
  LogMemo.Repaint;
end;

procedure ShowDetailsClick(Sender: TObject);
begin
  DetailsVisible := not DetailsVisible;
  LogMemo.Visible := DetailsVisible;
  if DetailsVisible then
    DetailsButton.Caption := 'Hide details'
  else
    DetailsButton.Caption := 'Show details';
end;

procedure CurInstallProgressChanged(CurProgress, MaxProgress: Integer);
var
  S, F: string;
begin
  S := WizardForm.StatusLabel.Caption;
  F := WizardForm.FilenameLabel.Caption;
  if (S <> '') and (S <> LastStatus) then
  begin
    LastStatus := S;
    AddLog('- ' + S);
  end;
  if (F <> '') and (F <> LastFile) then
  begin
    LastFile := F;
    AddLog('    ' + F);
  end;
  WizardForm.StatusLabel.Caption := 'Output folder: ' + WizardForm.DirEdit.Text;
end;
  
{ ===================================================
  FORCE CLOSE RUNNING AUTOPILOT COMPONENTS
=================================================== }
procedure CloseRunningAutoPilotProcesses;
var
  ResultCode: Integer;
begin
  { --- CLOSE AUTOPILOT APPLICATIONS --- }
  Exec('taskkill', '/IM Dashboard.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/IM CommandsEditor.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/IM ScriptsEditor.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/IM FileStorage.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/IM Lock.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/IM Updater.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/IM Data.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/IM Settings.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/IM SettingsScripts.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/IM NetMonitor.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/IM SystemMonitor.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/IM ProcessManager.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

  { --- CLOSE ALL AUTOPILOT POWERSHELL SCRIPTS --- }
  Exec(ExpandConstant('{win}\System32\WindowsPowerShell\v1.0\powershell.exe'),
    '-Command "Get-CimInstance Win32_Process | Where-Object {' +
    '$_.CommandLine -like ''*Autopilot.ps1*'' -or ' +
    '$_.CommandLine -like ''*Defender.ps1*'' -or ' +
    '$_.CommandLine -like ''*Pi.ps1*'' -or ' +
    '$_.CommandLine -like ''*Docker.ps1*'' -or ' +
    '$_.CommandLine -like ''*Cleaner.ps1*'' -or ' +
    '$_.CommandLine -like ''*Network.ps1*'' -or ' +
    '$_.CommandLine -like ''*NetTraffic.ps1*'' -or ' +
    '$_.CommandLine -like ''*SetDocker.ps1*'' -or ' +
    '$_.CommandLine -like ''*PowerPlan.ps1*'' -or ' +
    '$_.CommandLine -like ''*TrafficMonitorWorker.ps1*'' -or ' +
    '$_.CommandLine -like ''*SystemMonitorWorker.ps1*''} ' +
    '| ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

{ ===================================================
  INITIALIZE WIZARD
=================================================== }
procedure InitializeWizard();
var
  LogoPath: string;
  DetailsTop: Integer;
begin
  // Дозволи корисникот да го избере патот (first install)
  WizardForm.DirEdit.ReadOnly := False;

  try
    ExtractTemporaryFile('autopilot.bmp');
    LogoPath := ExpandConstant('{tmp}\autopilot.bmp');
    if FileExists(LogoPath) then
    begin
      { Use the AutoPilot logo in place of the standard folder picture
        on the Select Destination Location page. }
      WizardForm.SelectDirBitmapImage.Bitmap.LoadFromFile(LogoPath);
      WizardForm.SelectDirBitmapImage.Bitmap.AlphaFormat := afDefined;
      WizardForm.SelectDirBitmapImage.Stretch := True;
      WizardForm.SelectDirLabel.Caption :=
        'Setup will install AutoPilot Automation System into the following folder.';
      WizardForm.SelectDirBrowseLabel.Caption :=
        'To continue, click Next. To choose a different folder, click Browse.';
    end;
  except
    { Keep Setup usable if the optional header logo cannot be loaded. }
  end;

  { Keep the standard installation page with the logo in its upper-right corner. }
  WizardForm.FilenameLabel.Visible := False;
  WizardForm.ProgressGauge.Top := WizardForm.StatusLabel.Top +
    WizardForm.StatusLabel.Height + ScaleY(4);
  DetailsTop := WizardForm.ProgressGauge.Top + WizardForm.ProgressGauge.Height + ScaleY(8);

  DetailsButton := TNewButton.Create(WizardForm);
  DetailsButton.Parent := WizardForm.InstallingPage;
  DetailsButton.Caption := 'Show details';
  DetailsButton.Left := ScaleX(4);
  DetailsButton.Top := DetailsTop;
  DetailsButton.Width := ScaleX(88);
  DetailsButton.Height := ScaleY(23);
  DetailsButton.OnClick := @ShowDetailsClick;
  DetailsButton.Visible := True;

  LogMemo := TNewMemo.Create(WizardForm);
  LogMemo.Parent := WizardForm.InstallingPage;
  LogMemo.Left := 0;
  LogMemo.Top := DetailsTop + ScaleY(30);
  LogMemo.Width := WizardForm.InstallingPage.ClientWidth;
  LogMemo.Height := WizardForm.InstallingPage.ClientHeight - LogMemo.Top;
  LogMemo.ScrollBars := ssVertical;
  LogMemo.ReadOnly := True;
  LogMemo.WordWrap := True;
  LogMemo.Font.Name := 'Segoe UI';
  LogMemo.Font.Size := 9;
  LogMemo.Anchors := [akLeft, akTop, akRight, akBottom];
  LogMemo.Visible := False;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
    SetupFinished := True;

  if CurPageID = wpInstalling then
  begin
    WizardForm.PageDescriptionLabel.Visible := True;
    WizardForm.StatusLabel.Caption := 'Output folder: ' + WizardForm.DirEdit.Text;
  end;
end;

procedure DeinitializeSetup();
begin
  if SetupFinished then
    DeleteFile(ExpandConstant('{app}\PawnIO_setup.exe'));
end;

{ ===================================================
  PAWNIO SILENT INSTALL AND UNINSTALL
=================================================== }
function GetPawnIODir: string;
var
  InstallDir: string;
begin
  InstallDir := '';
  if not RegQueryStringValue(HKLM64,
    'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO',
    'InstallLocation', InstallDir) then
    RegQueryStringValue(HKLM32,
      'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO',
      'InstallLocation', InstallDir);

  if InstallDir = '' then
    InstallDir := 'C:\Program Files\PawnIO';
  Result := RemoveBackslash(InstallDir);
end;

function IsPawnIOInstalled: Boolean;
var
  PawnIODir: string;
begin
  PawnIODir := GetPawnIODir;
  Result :=
    (RegKeyExists(HKLM64, 'SYSTEM\CurrentControlSet\Services\PawnIO') or
     RegKeyExists(HKLM32, 'SYSTEM\CurrentControlSet\Services\PawnIO')) and
    FileExists(PawnIODir + '\PawnIOLib.dll') and
    FileExists(PawnIODir + '\PawnIOUtil.exe');
end;

function HasPawnIORemnants: Boolean;
begin
  Result :=
    RegKeyExists(HKLM64, 'SYSTEM\CurrentControlSet\Services\PawnIO') or
    RegKeyExists(HKLM32, 'SYSTEM\CurrentControlSet\Services\PawnIO') or
    RegKeyExists(HKLM64, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO') or
    RegKeyExists(HKLM32, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO') or
    DirExists(GetPawnIODir);
end;

procedure InstallPawnIOSilent;
var
  InstallerPath: string;
  Code: Integer;
  InstallSucceeded: Boolean;
begin
  if IsPawnIOInstalled then
  begin
    AddLog('PawnIO is already installed. Skipping installation.');
    Exit;
  end;

  ExtractTemporaryFile('PawnIO_setup.exe');
  InstallerPath := ExpandConstant('{tmp}\PawnIO_setup.exe');
  if not FileExists(InstallerPath) then
  begin
    AddLog('PawnIO installer package is missing.');
    Exit;
  end;

  if HasPawnIORemnants then
  begin
    AddLog('Removing incomplete PawnIO installation...');
    Exec(InstallerPath, '-uninstall -silent', ExtractFilePath(InstallerPath), SW_HIDE, ewWaitUntilTerminated, Code);
  end;

  AddLog('Installing PawnIO...');
  InstallSucceeded := Exec(InstallerPath, '-install -silent', ExtractFilePath(InstallerPath), SW_HIDE, ewWaitUntilTerminated, Code);
  if InstallSucceeded and ((Code = 0) or (Code = 3010)) then
    AddLog('PawnIO is now installed.')
  else if IsPawnIOInstalled then
    AddLog('PawnIO is installed.')
  else
    AddLog('PawnIO is not installed.');
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  PawnIOSetupPath: string;
  Code: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    PawnIOSetupPath := ExpandConstant('{app}\PawnIO_setup.exe');
    if FileExists(PawnIOSetupPath) then
      Exec(PawnIOSetupPath, '-uninstall -silent', ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, Code);
  end;
end;

{ ===================================================
  DELETE INSTALLERS FOLDER AFTER INSTALLATION
=================================================== }
procedure DeleteInstallerFiles;
var
  InstallersPath: string;
begin
  InstallersPath := ExpandConstant('{app}\installers');
  if DirExists(InstallersPath) then
    DelTree(InstallersPath, True, True, True);  // True = recursive + force
end;

{ ===================================================
  DELETE EXTERNAL BACKUP FOLDER (CREATED BY UPDATER)
=================================================== }
procedure DeleteExternalBackup;
var
  BackupPath: string;
begin
  BackupPath := ExpandConstant('{app}_Backup');
  if DirExists(BackupPath) then
    DelTree(BackupPath, True, True, True);
end;

{ ===================================================
  CREATE SHORTCUTS FOR ALL SCRIPTS
=================================================== }
procedure CreateShortcuts;
var
  ShellLink: Variant;
  WshShell: Variant;
  ShortcutFolder: string;
  PSPath: string;
  ScriptList: array[0..8] of string;
  ShortcutName: array[0..8] of string;
  i: Integer;
begin
  ShortcutFolder := ExpandConstant('{app}\Shortcuts');

  if not DirExists(ShortcutFolder) then
    ForceDirectories(ShortcutFolder);

  PSPath := ExpandConstant('{win}\System32\WindowsPowerShell\v1.0\powershell.exe');

  ScriptList[0] := 'Autopilot.ps1'; ShortcutName[0] := 'AutoPilot.lnk';
  ScriptList[1] := 'Defender.ps1'; ShortcutName[1] := 'Defender.lnk';
  ScriptList[2] := 'Pi.ps1';       ShortcutName[2] := 'Pi.lnk';
  ScriptList[3] := 'Docker.ps1';   ShortcutName[3] := 'Docker.lnk';
  ScriptList[4] := 'Cleaner.ps1';  ShortcutName[4] := 'Cleaner.lnk';
  ScriptList[5] := 'Network.ps1';  ShortcutName[5] := 'Network.lnk';
  ScriptList[6] := 'NetTraffic.ps1'; ShortcutName[6] := 'NetTraffic.lnk';
  ScriptList[7] := 'SetDocker.ps1'; ShortcutName[7] := 'SetDocker.lnk';
  ScriptList[8] := 'PowerPlan.ps1'; ShortcutName[8] := 'PowerPlan.lnk';

  WshShell := CreateOleObject('WScript.Shell');

  for i := 0 to 8 do
  begin
    ShellLink := WshShell.CreateShortcut(ShortcutFolder + '\' + ShortcutName[i]);
    ShellLink.TargetPath := PSPath;
    ShellLink.Arguments := '-ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\') + ScriptList[i] + '"';
    ShellLink.WorkingDirectory := ExpandConstant('{app}');
    ShellLink.Save;
  end;
end;

{ ===================================================
  POST-INSTALL STEP
=================================================== }
procedure CurStepChanged(CurStep: TSetupStep);
var
  InstallPath: string;
begin
  if CurStep = ssInstall then
begin
  { --- CLOSE RUNNING AUTOPILOT COMPONENTS --- }
  AddLog('Preparing installation...');
  CloseRunningAutoPilotProcesses();

  InstallPath := WizardForm.DirEdit.Text;
  AddLog('Installing AutoPilot to: ' + InstallPath);
end;

  if CurStep = ssPostInstall then
  begin
    WizardForm.StatusLabel.Caption := 'Finalizing installation...';
    WizardForm.Repaint;

    { Install PawnIO silently, without prompts or PawnIO-specific messages. }
    InstallPawnIOSilent();

    { --- CLEAN UP INSTALLER FILES --- }
    WizardForm.StatusLabel.Caption := 'Cleaning up installer files...';
    WizardForm.Repaint;
    DeleteInstallerFiles();
    DeleteExternalBackup();

    { --- CREATE SHORTCUTS --- }
    WizardForm.StatusLabel.Caption := 'Creating shortcuts...';
    WizardForm.Repaint;
    CreateShortcuts();
    WizardForm.StatusLabel.Caption := 'Shortcuts created!';
    WizardForm.Repaint;

    WizardForm.StatusLabel.Caption := 'Installation completed!';
    WizardForm.ProgressGauge.Position := 100;
    WizardForm.Repaint;

    { --- ORIGINAL COMPLETION MESSAGE --- }
    MsgBox(
      'Installation completed!'#13#10 +
      'The installer files have been removed.',
      mbInformation, MB_OK
    );

    { ▶ OPTIONAL START APPLICATION AFTER SETUP CLOSES }
    if WizardIsTaskSelected('launchapp') then
    begin
      Exec(ExpandConstant('{app}\AutoPilot.exe'), '', '', SW_SHOW, ewNoWait, ResultCode);
    end;
  end;
end;
