<#
.SYNOPSIS
  Bulk-creates Active Directory users from a CSV file.
.DESCRIPTION
  For each row: builds a username (first initial + last name), creates a
  department OU if missing, creates the user (must change password at first
  logon), adds group memberships, and skips users that already exist.
  Writes a results log to C:\Scripts\Logs. Supports -WhatIf for a dry run.
.EXAMPLE
  .\New-LabUsers.ps1 -CsvPath C:\Scripts\new-hires.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CsvPath,
    [string]$BaseOU  = "OU=Users,OU=Lab,DC=homelab,DC=local",
    [string]$Domain  = "homelab.local",
    [string]$LogPath = "C:\Scripts\Logs\New-LabUsers_$(Get-Date -Format yyyyMMdd_HHmmss).csv"
)

Import-Module ActiveDirectory -ErrorAction Stop
$initialPassword = Read-Host -AsSecureString "Initial password for new users (they must change it at first logon)"
$start = Get-Date

$results = foreach ($row in Import-Csv $CsvPath) {
    $first = $row.FirstName.Trim()
    $last  = $row.LastName.Trim()
    $sam   = (($first.Substring(0,1) + $last).ToLower() -replace '[^a-z0-9]','')
    if ($sam.Length -gt 20) { $sam = $sam.Substring(0,20) }
    $ou    = "OU=$($row.Department),$BaseOU"

    try {
        if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ou'" -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess($ou, "Create OU")) {
                New-ADOrganizationalUnit -Name $row.Department -Path $BaseOU -ProtectedFromAccidentalDeletion $false
            }
        }

        if (Get-ADUser -Filter "SamAccountName -eq '$sam'") {
            [pscustomobject]@{ User = $sam; Status = 'Skipped (already exists)'; OU = $ou; Groups = '' }
            continue
        }

        if ($PSCmdlet.ShouldProcess($sam, "Create user in $ou")) {
            New-ADUser -Name "$first $last" -GivenName $first -Surname $last `
                -SamAccountName $sam -UserPrincipalName "$sam@$Domain" -DisplayName "$first $last" `
                -Department $row.Department -Title $row.Title -Path $ou `
                -AccountPassword $initialPassword -ChangePasswordAtLogon $true -Enabled $true

            $added = @()
            foreach ($g in ($row.Groups -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                Add-ADGroupMember -Identity $g -Members $sam
                $added += $g
            }
            [pscustomobject]@{ User = $sam; Status = 'Created'; OU = $ou; Groups = ($added -join ';') }
        }
    }
    catch {
        [pscustomobject]@{ User = $sam; Status = "FAILED: $($_.Exception.Message)"; OU = $ou; Groups = '' }
    }
}

$results | Export-Csv $LogPath -NoTypeInformation
$results | Format-Table -AutoSize
"Processed $(@($results).Count) users in $([math]::Round(((Get-Date) - $start).TotalSeconds,1)) seconds. Log: $LogPath"
