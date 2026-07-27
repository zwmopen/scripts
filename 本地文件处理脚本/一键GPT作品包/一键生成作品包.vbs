Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

Function QueryValue(url, key)
    Set re = New RegExp
    re.IgnoreCase = True
    re.Global = False
    re.Pattern = "[?&]" & key & "=([^&]+)"
    Set matches = re.Execute(url)
    If matches.Count > 0 Then
        QueryValue = matches(0).SubMatches(0)
    Else
        QueryValue = ""
    End If
End Function

isConfigure = False
protocolUrl = ""
If WScript.Arguments.Count > 0 Then
    protocolUrl = WScript.Arguments(0)
    isConfigure = InStr(1, LCase(protocolUrl), "configure", vbTextCompare) > 0
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
    batchId = QueryValue(protocolUrl, "batch")
    expectedCount = QueryValue(protocolUrl, "expected")
    If batchId <> "" Then
        command = command & " -BatchId " & Chr(34) & batchId & Chr(34)
    End If
    If expectedCount <> "" And IsNumeric(expectedCount) Then
        command = command & " -ExpectedImageCount " & CStr(CLng(expectedCount))
    End If
End If

shell.Run command, 0, False
