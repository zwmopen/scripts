Option Explicit

Dim shell, fso, http, stream, scriptPath, command, bootstrapUrl
If WScript.Arguments.Count > 0 Then
    If LCase(WScript.Arguments(0)) = "/check" Then
        WScript.Echo "VBS_OK"
        WScript.Quit 0
    End If
End If
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptPath = shell.ExpandEnvironmentStrings("%TEMP%") & "\install_gpt_work_package.ps1"
bootstrapUrl = "https://raw.githubusercontent.com/zwmopen/scripts/master/bootstrap_install.ps1"

On Error Resume Next
Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
http.Open "GET", bootstrapUrl, False
http.Send
If Err.Number <> 0 Or http.Status <> 200 Then
    MsgBox "Download failed. Please check the network and try again.", 16, "GPT Work Package Assistant"
    WScript.Quit 1
End If

Set stream = CreateObject("ADODB.Stream")
stream.Type = 1
stream.Open
stream.Write http.ResponseBody
stream.SaveToFile scriptPath, 2
stream.Close
If Err.Number <> 0 Then
    MsgBox "Cannot save the installer. Please try again.", 16, "GPT Work Package Assistant"
    WScript.Quit 1
End If
On Error GoTo 0

command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34)
shell.Run command, 0, False
