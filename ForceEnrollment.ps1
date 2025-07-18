<#
.SYNOPSIS
    This script enforces MDM enrollment for a device by creating necessary registry keys. It makes use of a scheduled tasks to run this script. The scheduled task is created during image builder process.
    It checks the device's join status (Entra Hybrid Join and Domain Join) and performs actions accordingly,
    including a forced reboot if required (once) which forces the MDM enrollment process to complete.

.DESCRIPTION
    - Creates registry keys required for MDM enrollment.
    - Configures scheduled tasks to run the script at startup.
    - Validates the device's Entra Hybrid Join and Domain Join status.
    - Forces a reboot if the device is not properly enrolled.
    - Logs all actions and progress to a log file for troubleshooting and auditing purposes.

.NOTES
    - Do not remove the registry key "HKLM:\Software\AVD Management\HybridRebootOccured" with the value "DONOTREMOVE".
      This key ensures that the script does not force another unnecessary reboot.
    - Verify the enrollment status in the Intune portal after the script completes.

.AUTHOR
    Joey Verlinden / Bastiaan Schumans
#>

# Required Tenant ID - MODIFY THE TENANT ID!
$tenantId = '5af8tsa3-****-****-****-**********'

# Required KeyPath - DO NOT MODIFY OR REMOVE!
$KeyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\$tenantId"

# Reboot validation path - DO NOT MODIFY OR REMOVE!
$rebootPath = "HKLM:\Software\AVD Management\HybridRebootOccured"
$rebootValueName = "DONOTREMOVE"

# Function to log messages with timestamps
function Write-Log {
    param (
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    Write-Host $logMessage
    Add-Content -Path "c:\windows\temp\Force_MDM_Erollment.log" -Value $logMessage
    }

# Create required registry keys
if (-not (Test-Path $KeyPath)) {
    New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo" -Name $tenantId -Force | Out-Null
    Write-Log "Registry key $KeyPath created."
} else {
    Write-Log "Registry key $KeyPath already exists. Skipping creation."
}


# These registry keys are being removed while running "dsregcmd /join". Therefore, they might be obsolete but kept in the script for ensurance
if ((Get-ItemProperty -Path $KeyPath -Name 'MdmEnrollmentUrl' -ErrorAction SilentlyContinue).MdmEnrollmentUrl -ne 'https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc') {
    New-ItemProperty -LiteralPath $KeyPath -Name 'MdmEnrollmentUrl' -Value 'https://enrollment.manage.microsoft.com/enrollmentserver/discovery.svc' -PropertyType String -Force -ErrorAction SilentlyContinue
    Write-Log "Updated or created 'MdmEnrollmentUrl' registry value."
} else {
    Write-Log "Registry setting 'MdmEnrollmentUrl' already exists and matches."
}

if ((Get-ItemProperty -Path $KeyPath -Name 'MdmTermsOfUseUrl' -ErrorAction SilentlyContinue).MdmTermsOfUseUrl -ne 'https://portal.manage.microsoft.com/TermsofUse.aspx') {
    New-ItemProperty -LiteralPath $KeyPath -Name 'MdmTermsOfUseUrl' -Value 'https://portal.manage.microsoft.com/TermsofUse.aspx' -PropertyType String -Force -ErrorAction SilentlyContinue
    Write-Log "Updated or created 'MdmTermsOfUseUrl' registry value."
} else {
    Write-Log "Registry setting 'MdmTermsOfUseUrl' already exists and matches."
}

if ((Get-ItemProperty -Path $KeyPath -Name 'MdmComplianceUrl' -ErrorAction SilentlyContinue).MdmComplianceUrl -ne 'https://portal.manage.microsoft.com/?portalAction=Compliance') {
    New-ItemProperty -LiteralPath $KeyPath -Name 'MdmComplianceUrl' -Value 'https://portal.manage.microsoft.com/?portalAction=Compliance' -PropertyType String -Force -ErrorAction SilentlyContinue
    Write-Log "Updated or created 'MdmComplianceUrl' registry value."
} else {
    Write-Log "Registry setting 'MdmComplianceUrl' already exists and matches."
}


# Check if the registry key and value exist
if ((Test-Path $rebootPath) -and (Get-ItemProperty -Path $rebootPath -Name $rebootValueName -ErrorAction SilentlyContinue)) {
    Write-Log "Reboot already performed. Skipping reboot logic."

    # Check for Event ID 72 in a loop
    Write-Log "Checking for Event ID 72 to verify enrollment..."
    while ($true) {
        $eventlog = Get-WinEvent -LogName "Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Enrollment" -FilterXPath "*[System[(EventID=72)]]" -MaxEvents 1 -ErrorAction SilentlyContinue

        if ($eventlog) {
            Write-Log "Event ID 72 detected in Event Viewer. Enrollment successful."
            break
        } else {
            Write-Log "Event ID 72 not found. Retrying..."
            Start-Sleep 30
        }
    }

    Write-Log "Script completed. Enrollment process completed. Verify in the Intune portal."

} else {
    # Loop to check Entra Hybrid Join status
    $attemptCount = 0
    while ($true) {
        $attemptCount++
        Write-Log "Checking Entra Hybrid Join status... Attempt $attemptCount"

        $dsreg = dsregcmd /status

        $EntraIDJoined = ($dsreg | Select-String "AzureAdJoined").ToString().Split(':')[1].Trim()
        $domainJoined = ($dsreg | Select-String "DomainJoined").ToString().Split(':')[1].Trim()

        if ($EntraIDJoined -eq "YES" -and $domainJoined -eq "YES") {
            Write-Log "Device is Entra Hybrid Joined. Rebooting the device in 2 minutes..."

            # Create the registry key and value to indicate the reboot has occurred
            if (-not (Test-Path $rebootPath)) {
                New-Item -Path $rebootPath -Force | Out-Null
            }
            Set-ItemProperty -Path $rebootPath -Name $rebootValueName -Value 1 -Type DWord -Force

            # Reboot the device
            Start-Sleep -Seconds 120
            Restart-Computer -Force
            break
        } elseif ($EntraIDJoined -eq "NO" -and $domainJoined -eq "YES") {
            Write-Log "Device is Domain Joined but not Entra ID Joined."

            # Execute Hybrid Join
            Write-Log "Executing dsregcmd /join command..."
            Start-Process -FilePath "$env:SystemRoot\System32\dsregcmd.exe" -ArgumentList "/join" -NoNewWindow -Wait

            # Wait for a short period to allow the join process to complete
            Start-Sleep 60
        } else {
            Write-Log "Device is NOT Entra Hybrid Joined."
            Write-Log "EntraIDJoined: $EntraIDJoined"
            Write-Log "DomainJoined: $domainJoined"
        }

        Start-Sleep 30
        Write-Log "Retrying Entra Hybrid Join status check..."
    }
}