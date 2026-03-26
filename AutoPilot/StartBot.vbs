Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Почекај 60 секунди
WScript.Sleep 60000 

' Папката каде што се наоѓа VBS фајлот
appPath = fso.GetParentFolderName(WScript.ScriptFullName)

' Стартувај PowerShell скрипта од истата папка
WshShell.Run "powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & appPath & "\Autopilot.ps1""", 0, False




