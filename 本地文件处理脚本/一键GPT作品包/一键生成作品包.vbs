Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

isConfigure = False
If WScript.Arguments.Count > 0 Then
    isConfigure = InStr(1, LCase(WScript.Arguments(0)), "configure", vbTextCompare) > 0
End If

If isConfigure Then
    scriptPath = fso.GetParentFolderName(WScript.ScriptFullName) & "\configure_work_package.ps1"
    command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34)
ElseIf WScript.Arguments.Count > 0 And InStr(1, LCase(WScript.Arguments(0)), "diagnose", vbTextCompare) > 0 Then
    scriptPath = fso.GetParentFolderName(WScript.ScriptFullName) & "\make_work_package.ps1"
    command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34) & " -Diagnose"
Else
    scriptPath = fso.GetParentFolderName(WScript.ScriptFullName) & "\make_work_package.ps1"
    command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34)
End If

shell.Run command, 0, False
