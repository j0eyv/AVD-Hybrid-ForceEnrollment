#Create ForceEnrollment task
$action = New-ScheduledTaskAction -Execute "$env:windir\System32\WindowsPowerShell\v1.0\Powershell.exe" -Argument "-executionPolicy Unrestricted -File `"$($env:SystemDrive)\ForceEnrollment.ps1`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal 'NT Authority\SYSTEM' -RunLevel Highest
$settingsSet = New-ScheduledTaskSettingsSet
$task = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settingsSet
Register-ScheduledTask -TaskName 'AVD-MDM-Enrollment' -InputObject $task -ErrorAction Ignore
Enable-ScheduledTask -TaskName 'AVD-MDM-Enrollment'
#End ForceEnrollment task