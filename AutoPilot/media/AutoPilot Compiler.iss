; ===================================================
; AutoPilot Installer - Full Version
; ===================================================

[Setup]
AppName=Autopilot Automation System
AppVersion=1.0.0
DefaultDirName=C:\AutoPilot
DefaultGroupName=AutoPilot
OutputBaseFilename=AutoPilot_SetUp
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
UninstallFilesDir={app}
DisableDirPage=no
SetupIconFile=AutoPilot\media\autopilot.ico
UninstallDisplayIcon={app}\AutoPilot.exe

[Files]
; Main application files – exclude runtime data folders
Source: "AutoPilot\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion; Excludes: Autopilot_Data\*,Data\*,Camera\*,JSON\*

; JSON folder – copy only if JSON folder не постои (fresh install)
Source: "AutoPilot\JSON\*"; DestDir: "{app}\JSON"; Flags: recursesubdirs ignoreversion onlyifdoesntexist

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
  IsFirstInstall: Boolean;
  
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
  Exec('taskkill', '/IM Camera.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/IM Lock.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('taskkill', '/IM Updater.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);


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
    '$_.CommandLine -like ''*TrafficMonitorWorker.ps1*''} ' +
    '| ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

{ ===================================================
  INITIALIZE WIZARD
=================================================== }
procedure InitializeWizard();
begin
  // Дозволи корисникот да го избере патот (first install)
  WizardForm.DirEdit.ReadOnly := False;
end;

{ ===================================================
  INSTALL LOCAL EXE WITH USER CONFIRMATION
=================================================== }
procedure InstallExeLocal(Name, FileName, Params: string);
var
  FilePath: string;
begin
  FilePath := ExpandConstant('{app}\installers\' + FileName);
  if MsgBox('Do you want to install ' + Name + '?'#13#10 +
            'IMPORTANT: This package is required for proper functionality of AutoPilot.',
            mbConfirmation, MB_YESNO) = IDYES then
  begin
    WizardForm.StatusLabel.Caption := 'Installing ' + Name + '...';
    WizardForm.ProgressGauge.Position := 0;
    WizardForm.Repaint;

    if Exec(FilePath, Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode) then
    begin
      if ResultCode <> 0 then
        MsgBox(Name + ' installer returned error code: ' + IntToStr(ResultCode), mbError, MB_OK);
    end
    else
      MsgBox('Failed to start ' + Name + ' installer.', mbError, MB_OK);

    WizardForm.StatusLabel.Caption := Name + ' installed.';
    WizardForm.ProgressGauge.Position := 100;
    WizardForm.Repaint;
  end
  else
  begin
    MsgBox('WARNING: If you skip installing ' + Name + ', AutoPilot may not work properly!',
           mbInformation, MB_OK);
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
  CloseRunningAutoPilotProcesses();

  InstallPath := WizardForm.DirEdit.Text;
  IsFirstInstall := not DirExists(InstallPath);
end;

  if CurStep = ssPostInstall then
  begin
    WizardForm.StatusLabel.Caption := 'Finalizing installation...';
    WizardForm.Repaint;

    { --- INSTALL PACKAGES WITH CONFIRMATION --- }
    InstallExeLocal('PawnIO', 'PawnIO_setup.exe', '');

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
      'IMPORTANT: If you skipped installing any dependency, AutoPilot may not work properly.'#13#10 +
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