Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(root, "Dorion-with-proxy.ps1")
setupPath = fso.BuildPath(root, "Setup-proxy.ps1")
configPath = fso.BuildPath(root, "proxy-config.json")

If Not fso.FileExists(configPath) Then
    setupCommand = "powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & setupPath & Chr(34)
    shell.Run setupCommand, 0, True
End If

If Not fso.FileExists(configPath) Then
    MsgBox "Proxy is not configured. Run Setup-proxy.bat first.", vbExclamation, "Dorion proxy"
    WScript.Quit 1
End If

command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & scriptPath & Chr(34)

shell.Run command, 0, False
