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
isCenter = False
protocolUrl = ""
If WScript.Arguments.Count > 0 Then
    protocolUrl = WScript.Arguments(0)
    isConfigure = InStr(1, LCase(protocolUrl), "configure", vbTextCompare) > 0
    isCenter = InStr(1, LCase(protocolUrl), "center", vbTextCompare) > 0
End If

Function ResolveScript(scriptName)
    Dim baseDir
    baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
    If fso.FileExists(baseDir & "\" & scriptName) Then
        ResolveScript = baseDir & "\" & scriptName
    ElseIf fso.FileExists(baseDir & "\GPT作品助手\" & scriptName) Then
        ResolveScript = baseDir & "\GPT作品助手\" & scriptName
    ElseIf fso.FileExists(baseDir & "\GPT作品助手\工具脚本\" & scriptName) Then
        ResolveScript = baseDir & "\GPT作品助手\工具脚本\" & scriptName
    ElseIf fso.FileExists("D:\AICode\运行数据\chatgpt-work-package\" & scriptName) Then
        ResolveScript = "D:\AICode\运行数据\chatgpt-work-package\" & scriptName
    Else
        ResolveScript = baseDir & "\" & scriptName
    End If
End Function

If isConfigure Then
    scriptPath = ResolveScript("work_package_center.ps1")
    command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34) & " -InitialTab Settings"
ElseIf isCenter Then
    scriptPath = ResolveScript("work_package_center.ps1")
    command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34) & " -InitialTab Tasks"
ElseIf WScript.Arguments.Count > 0 And InStr(1, LCase(WScript.Arguments(0)), "diagnose", vbTextCompare) > 0 Then
    scriptPath = ResolveScript("make_work_package.ps1")
    command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34) & " -Diagnose"
Else
    scriptPath = ResolveScript("make_work_package.ps1")
    command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34)
    batchId = QueryValue(protocolUrl, "batch")
    expectedCount = QueryValue(protocolUrl, "expected")
    targetDest = QueryValue(protocolUrl, "target")
    If batchId <> "" Then
        command = command & " -BatchId " & Chr(34) & batchId & Chr(34)
    End If
    If expectedCount <> "" And IsNumeric(expectedCount) Then
        command = command & " -ExpectedImageCount " & CStr(CLng(expectedCount))
    End If
    If targetDest <> "" Then
        command = command & " -TargetDestination " & Chr(34) & targetDest & Chr(34)
    End If
End If

shell.Run command, 0, False
