Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)

If WScript.Arguments.Count = 0 Then
  WScript.Quit 1
End If

target = fso.BuildPath(scriptDir, WScript.Arguments(0))
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & target & Chr(34)
shell.Run command, 0, False
