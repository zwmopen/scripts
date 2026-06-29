Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)

If WScript.Arguments.Count = 0 Then
  WScript.Quit 1
End If

target = fso.BuildPath(scriptDir, WScript.Arguments(0))
extraArgs = ""
For i = 1 To WScript.Arguments.Count - 1
  extraArgs = extraArgs & " " & WScript.Arguments(i)
Next

command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & target & Chr(34) & extraArgs
shell.Run command, 0, False
