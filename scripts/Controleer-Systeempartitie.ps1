<#
.SYNOPSIS
    Controleert de door het systeem gereserveerde partitie / EFI-systeempartitie
    voordat je (opnieuw) naar Windows 11 upgradet.

.DESCRIPTION
    Dit script wijzigt NIETS aan je computer. Het toont alleen:
      - de partitiestijl van de opstartschijf (GPT of MBR);
      - de grootte en vrije ruimte van de systeempartitie;
      - waar de Windows Herstelomgeving (WinRE) staat;
      - een advies welke stap uit docs/windows11-systeempartitie.md je moet volgen.

    Uitvoeren in PowerShell als Administrator:
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
        .\Controleer-Systeempartitie.ps1
#>

[CmdletBinding()]
param(
    # Minimale vrije ruimte (MB) die Windows Setup doorgaans nodig heeft op de systeempartitie.
    [int]$MinimaalVrijMB = 15
)

$ErrorActionPreference = 'Stop'

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning 'Start PowerShell als Administrator (rechtsklik > Als administrator uitvoeren) en probeer opnieuw.'
    exit 1
}

$systeemPartitie = Get-Partition | Where-Object { $_.IsSystem } | Select-Object -First 1
if (-not $systeemPartitie) {
    # MBR-schijven: de actieve partitie is de systeempartitie
    $systeemPartitie = Get-Partition | Where-Object { $_.IsActive } | Select-Object -First 1
}
if (-not $systeemPartitie) {
    Write-Warning 'Er is geen systeempartitie gevonden.'
    exit 1
}

$schijf    = Get-Disk -Number $systeemPartitie.DiskNumber
$volume    = Get-Volume -Partition $systeemPartitie
$grootteMB = [math]::Round($systeemPartitie.Size / 1MB)
$vrijMB    = [math]::Round($volume.SizeRemaining / 1MB)

Write-Host ''
Write-Host '=== Systeempartitie ===' -ForegroundColor Cyan
Write-Host ("Schijf          : {0} ({1})" -f $schijf.Number, $schijf.FriendlyName)
Write-Host ("Partitiestijl   : {0}" -f $schijf.PartitionStyle)
Write-Host ("Partitienummer  : {0}" -f $systeemPartitie.PartitionNumber)
Write-Host ("Label           : {0}" -f $volume.FileSystemLabel)
Write-Host ("Bestandssysteem : {0}" -f $volume.FileSystem)
Write-Host ("Grootte         : {0} MB" -f $grootteMB)
Write-Host ("Vrije ruimte    : {0} MB" -f $vrijMB)

Write-Host ''
Write-Host '=== Windows Herstelomgeving (reagentc /info) ===' -ForegroundColor Cyan
& reagentc.exe /info

Write-Host ''
Write-Host '=== Advies ===' -ForegroundColor Cyan
if ($vrijMB -ge $MinimaalVrijMB) {
    Write-Host ("Er is {0} MB vrij (minimaal ~{1} MB nodig). De partitie lijkt voldoende ruimte te hebben." -f $vrijMB, $MinimaalVrijMB) -ForegroundColor Green
    Write-Host 'Blijft de fout terugkomen? Volg dan stap 5 en 6 in docs/windows11-systeempartitie.md.'
}
elseif ($schijf.PartitionStyle -eq 'GPT') {
    Write-Host ("Te weinig vrije ruimte ({0} MB). Volg stap 3A (GPT/UEFI) in docs/windows11-systeempartitie.md." -f $vrijMB) -ForegroundColor Yellow
}
else {
    Write-Host ("Te weinig vrije ruimte ({0} MB). Volg stap 3B (MBR/Legacy) in docs/windows11-systeempartitie.md." -f $vrijMB) -ForegroundColor Yellow
}

if ($schijf.PartitionStyle -eq 'MBR') {
    Write-Host 'Let op: Windows 11 vereist UEFI met Secure Boot. Een MBR-schijf moet je eerst omzetten naar GPT (zie stap 4).' -ForegroundColor Yellow
}
