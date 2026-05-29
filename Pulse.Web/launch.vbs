' Pulse Web — Hidden Launcher
' Runs run.bat in silent mode with no visible console window.
' All output is captured to pulse-server.log for viewing inside the Pulse UI.

Set fso = CreateObject("Scripting.FileSystemObject")
strDir = fso.GetParentFolderName(WScript.ScriptFullName)

Set sh = CreateObject("WScript.Shell")
sh.CurrentDirectory = strDir

' Window style 0 = hidden; run.bat --silent skips pause commands
sh.Run "cmd /c """ & strDir & "\run.bat"" --silent > """ & strDir & "\pulse-server.log"" 2>&1", 0, False
