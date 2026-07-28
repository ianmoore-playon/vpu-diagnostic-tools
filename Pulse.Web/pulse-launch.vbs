' ─────────────────────────────────────────────────────────────
' pulse-launch.vbs — start the Pulse server with NO visible window
'
' Launched by run.bat once setup is complete. Runs the embedded
' Python server fully detached and hidden, so there's no console
' window for anyone to click into (a stray click in a Windows
' console with QuickEdit on would freeze the server).
'
' Server stdout/stderr is intentionally discarded — the app mirrors
' everything to pulse-server.log, which the Server Log tab reads.
' ─────────────────────────────────────────────────────────────
Option Explicit

Dim fso, sh, scriptDir, exe, pyw, py, mainPy

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
pyw    = scriptDir & "\app\python\pythonw.exe"
py     = scriptDir & "\app\python\python.exe"
mainPy = scriptDir & "\app\main.py"

' Prefer pythonw.exe (no console at all); fall back to python.exe.
If fso.FileExists(pyw) Then
    exe = pyw
Else
    exe = py
End If

sh.CurrentDirectory = scriptDir

' Window style 0 = hidden, False = don't wait (fully detached — the
' server keeps running after this script and the launcher both exit).
sh.Run """" & exe & """ """ & mainPy & """", 0, False
