Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptPath = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName)) & "\WindowLayout.ps1"
layoutPath = "D:\tools\窗口布局启动器\layouts\素材处理布局.json"
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34) & " -Mode Restore -ConfigPath " & Chr(34) & layoutPath & Chr(34)

shell.Run command, 0, False