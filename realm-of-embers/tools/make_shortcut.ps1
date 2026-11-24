$ws = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$sc = $ws.CreateShortcut("$desktop\王国余烬.lnk")
$sc.TargetPath = 'D:\ycharmProjects\godot\Godot_v4.3-stable_win64.exe'
$sc.Arguments = '--path "D:\ycharmProjects\game\realm-of-embers"'
$sc.WorkingDirectory = 'D:\ycharmProjects\game\realm-of-embers'
$sc.Description = '王国余烬 - Kingdom of Embers'
$sc.Save()
Write-Output "OK: $desktop\王国余烬.lnk"
