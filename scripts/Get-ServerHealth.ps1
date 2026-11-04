<#
.SYNOPSIS
  Generates a health report for a Windows server (disk, memory, services, events, uptime).
.DESCRIPTION
  Checks disk free space, memory usage, critical domain controller services, and
  recent System log errors. Prints a colour-coded PASS/WARN/FAIL summary and saves
  an HTML report to C:\Scripts\Reports.
.EXAMPLE
  .\Get-ServerHealth.ps1
#>
[CmdletBinding()]
param(
    [string]$ComputerName = $env:COMPUTERNAME,
    [string[]]$Services   = @('NTDS','DNS','DHCPServer','Netlogon','Kdc','W32Time'),
    [string]$ReportDir    = 'C:\Scripts\Reports'
)

$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check($Category, $Item, $Value, $Status) {
    $checks.Add([pscustomobject]@{ Category = $Category; Item = $Item; Value = $Value; Status = $Status })
}

# Disk
Get-CimInstance Win32_LogicalDisk -ComputerName $ComputerName -Filter "DriveType=3" | ForEach-Object {
    $pct = [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
    $status = if ($pct -lt 10) {'FAIL'} elseif ($pct -lt 20) {'WARN'} else {'PASS'}
    Add-Check 'Disk' $_.DeviceID ("{0}% free ({1:N1} GB of {2:N1} GB)" -f $pct, ($_.FreeSpace/1GB), ($_.Size/1GB)) $status
}

# Memory and uptime
$os = Get-CimInstance Win32_OperatingSystem -ComputerName $ComputerName
$memUsed = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 1)
$memStatus = if ($memUsed -gt 95) {'FAIL'} elseif ($memUsed -gt 85) {'WARN'} else {'PASS'}
Add-Check 'Memory' 'RAM used' ("{0}% of {1:N1} GB" -f $memUsed, ($os.TotalVisibleMemorySize/1MB)) $memStatus
$uptime = (Get-Date) - $os.LastBootUpTime
Add-Check 'System' 'Uptime' ("{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes) 'INFO'

# Services
foreach ($svc in $Services) {
    $s = Get-Service -Name $svc -ComputerName $ComputerName -ErrorAction SilentlyContinue
    if (-not $s)                  { Add-Check 'Service' $svc 'Not installed' 'WARN' }
    elseif ($s.Status -ne 'Running') { Add-Check 'Service' "$svc ($($s.DisplayName))" $s.Status 'FAIL' }
    else                          { Add-Check 'Service' "$svc ($($s.DisplayName))" 'Running' 'PASS' }
}

# Recent System log errors
$since  = (Get-Date).AddHours(-24)
$errors = @(Get-WinEvent -ComputerName $ComputerName -FilterHashtable @{ LogName='System'; Level=1,2; StartTime=$since } -ErrorAction SilentlyContinue)
$evStatus = if ($errors.Count -gt 10) {'FAIL'} elseif ($errors.Count -gt 0) {'WARN'} else {'PASS'}
Add-Check 'Events' 'System errors (24h)' "$($errors.Count) critical/error events" $evStatus
$topErrors = $errors | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 5 Count, Name

# Console output
$colors = @{ PASS = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'Cyan' }
Write-Host "`nHealth report for $ComputerName - $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n" -ForegroundColor White
foreach ($c in $checks) {
    Write-Host ("[{0,-4}] {1,-8} {2,-45} {3}" -f $c.Status, $c.Category, $c.Item, $c.Value) -ForegroundColor $colors[$c.Status]
}
$overall = if ($checks.Status -contains 'FAIL') {'FAIL'} elseif ($checks.Status -contains 'WARN') {'WARN'} else {'PASS'}
Write-Host "`nOverall: $overall" -ForegroundColor $colors[$overall]

# HTML report
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
$file = Join-Path $ReportDir ("Health_{0}_{1}.html" -f $ComputerName, (Get-Date -Format yyyyMMdd_HHmm))
$style = @"
<style>
body{font-family:Segoe UI,Arial;margin:24px;color:#222}
h1{font-size:20px} table{border-collapse:collapse;margin-bottom:20px}
th,td{border:1px solid #ccc;padding:6px 10px;text-align:left} th{background:#f0f0f0}
.PASS{background:#d4edda}.WARN{background:#fff3cd}.FAIL{background:#f8d7da}.INFO{background:#d1ecf1}
</style>
"@
$rows = ($checks | ForEach-Object { "<tr class='$($_.Status)'><td>$($_.Status)</td><td>$($_.Category)</td><td>$($_.Item)</td><td>$($_.Value)</td></tr>" }) -join "`n"
$errRows = if ($topErrors) { ($topErrors | ForEach-Object { "<tr><td>$($_.Count)</td><td>$($_.Name)</td></tr>" }) -join "`n" } else { "<tr><td colspan='2'>None</td></tr>" }
@"
<html><head><title>Health - $ComputerName</title>$style</head><body>
<h1>Server health: $ComputerName</h1>
<p>Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') &middot; Overall: <b class='$overall'>&nbsp;$overall&nbsp;</b></p>
<table><tr><th>Status</th><th>Category</th><th>Item</th><th>Value</th></tr>
$rows
</table>
<h2 style='font-size:16px'>Top System error sources (24h)</h2>
<table><tr><th>Count</th><th>Source</th></tr>
$errRows
</table></body></html>
"@ | Set-Content $file -Encoding UTF8
Write-Host "HTML report: $file`n" -ForegroundColor White
