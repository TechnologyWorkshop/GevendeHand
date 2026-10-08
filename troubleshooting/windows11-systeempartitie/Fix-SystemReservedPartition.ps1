<#
.SYNOPSIS
    Controleert en herstelt de fout "De door het systeem gereserveerde partitie kan niet worden bijgewerkt"
    (0xc1900104 / 0x800f0922) bij een upgrade naar Windows 11.

.DESCRIPTION
    Zonder parameters voert het script alleen een controle uit (er wordt niets gewijzigd):
      - zoekt de systeempartitie (EFI-systeempartitie op GPT, of "Systeem gereserveerd" op MBR);
      - koppelt die tijdelijk aan een vrije stationsletter;
      - toont grootte en vrije ruimte, en de grootste bestanden.

    Met -Fix wordt ruimte vrijgemaakt volgens de door Microsoft gedocumenteerde methode:
    de lettertypebestanden in de map Boot\Fonts worden verwijderd. Ze worden eerst
    gekopieerd naar een backupmap. Windows heeft deze bestanden niet nodig om op te starten;
    Windows Setup zet ze tijdens de upgrade zelf terug.

    Het script moet als Administrator worden uitgevoerd.

.PARAMETER Fix
    Verwijder de lettertypebestanden (na backup) om ruimte vrij te maken.

.PARAMETER BackupPath
    Map waarin de lettertypebestanden worden bewaard voordat ze worden verwijderd.

.EXAMPLE
    .\Fix-SystemReservedPartition.ps1
    Alleen controleren.

.EXAMPLE
    .\Fix-SystemReservedPartition.ps1 -Fix
    Controleren en ruimte vrijmaken.

.LINK
    https://support.microsoft.com/help/4051701
#>
[CmdletBinding()]
param(
    [switch]$Fix,
    [string]$BackupPath = (Join-Path $env:SystemDrive 'SystemPartitionFontsBackup')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows Setup heeft minimaal 15 MB vrije ruimte nodig op de systeempartitie.
$MinimumFreeMB = 15

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-FreeDriveLetter {
    $used = [System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1).ToUpperInvariant() }
    foreach ($letter in 'Z', 'Y', 'X', 'W', 'V', 'U', 'T', 'S') {
        if ($used -notcontains $letter) { return $letter }
    }
    throw 'Geen vrije stationsletter gevonden (S t/m Z zijn allemaal in gebruik).'
}

if (-not (Test-IsAdministrator)) {
    Write-Error 'Start PowerShell als Administrator (rechtsklik > "Als administrator uitvoeren") en probeer opnieuw.'
    exit 1
}

$systemPartition = Get-Partition | Where-Object { $_.IsSystem } | Select-Object -First 1
if (-not $systemPartition) {
    Write-Error 'Geen systeempartitie gevonden. Zie README.md voor handmatige stappen.'
    exit 1
}

$disk = Get-Disk -Number $systemPartition.DiskNumber
$isGpt = $disk.PartitionStyle -eq 'GPT'
$sizeMB = [math]::Round($systemPartition.Size / 1MB)

Write-Host ''
Write-Host '=== Systeempartitie ===' -ForegroundColor Cyan
Write-Host ("Schijf          : {0} ({1})" -f $disk.Number, $disk.PartitionStyle)
Write-Host ("Partitie        : {0}" -f $systemPartition.PartitionNumber)
Write-Host ("Type            : {0}" -f $(if ($isGpt) { 'EFI-systeempartitie' } else { 'Systeem gereserveerd (MBR)' }))
Write-Host ("Grootte         : {0} MB" -f $sizeMB)

$letter = Get-FreeDriveLetter
$root = "${letter}:\"
$mounted = $false
$exitCode = 0

try {
    if ($isGpt) {
        & mountvol.exe "${letter}:" /s | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "mountvol ${letter}: /s is mislukt (code $LASTEXITCODE)." }
    }
    else {
        Add-PartitionAccessPath -DiskNumber $systemPartition.DiskNumber `
            -PartitionNumber $systemPartition.PartitionNumber -AccessPath $root
    }
    $mounted = $true

    $drive = New-Object System.IO.DriveInfo($root)
    $freeMB = [math]::Round($drive.AvailableFreeSpace / 1MB, 1)
    Write-Host ("Vrije ruimte    : {0} MB (minimaal {1} MB nodig)" -f $freeMB, $MinimumFreeMB)

    Write-Host ''
    Write-Host '=== Grootste bestanden op de systeempartitie ===' -ForegroundColor Cyan
    Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
        Sort-Object Length -Descending |
        Select-Object -First 15 @{ n = 'KB'; e = { [math]::Round($_.Length / 1KB) } }, FullName |
        Format-Table -AutoSize | Out-Host

    $fontsPath = if ($isGpt) { Join-Path $root 'EFI\Microsoft\Boot\Fonts' } else { Join-Path $root 'Boot\Fonts' }
    $fontFiles = @()
    if (Test-Path -LiteralPath $fontsPath) {
        $fontFiles = @(Get-ChildItem -LiteralPath $fontsPath -File -Force)
    }
    $fontsBytes = 0
    foreach ($file in $fontFiles) { $fontsBytes += $file.Length }
    $fontsMB = [math]::Round($fontsBytes / 1MB, 1)
    Write-Host ("Lettertypebestanden in {0}: {1} bestand(en), {2} MB" -f $fontsPath, $fontFiles.Count, $fontsMB)

    if ($freeMB -ge $MinimumFreeMB) {
        Write-Host ''
        Write-Host 'Er is voldoende vrije ruimte. Zie README.md voor andere oorzaken.' -ForegroundColor Green
    }
    elseif (-not $Fix) {
        Write-Host ''
        Write-Host 'Te weinig vrije ruimte. Voer het script opnieuw uit met -Fix om ruimte vrij te maken.' -ForegroundColor Yellow
        $exitCode = 2
    }

    if ($Fix) {
        if ($fontFiles.Count -eq 0) {
            Write-Warning 'Er zijn geen lettertypebestanden om te verwijderen. Zie README.md (partitie vergroten).'
            $exitCode = 2
        }
        else {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $backupDir = Join-Path $BackupPath $stamp
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            Write-Host ''
            Write-Host "Backup van lettertypebestanden naar $backupDir ..." -ForegroundColor Cyan
            foreach ($file in $fontFiles) {
                Copy-Item -LiteralPath $file.FullName -Destination $backupDir -Force
            }

            if (-not $isGpt) {
                # Op MBR (NTFS) zijn de bestanden eigendom van SYSTEM; neem alleen van deze bestanden het eigendom over.
                foreach ($file in $fontFiles) {
                    & takeown.exe /f $file.FullName /a | Out-Null
                    & icacls.exe $file.FullName /grant '*S-1-5-32-544:F' | Out-Null
                }
            }

            foreach ($file in $fontFiles) {
                Remove-Item -LiteralPath $file.FullName -Force
            }

            $drive = New-Object System.IO.DriveInfo($root)
            $freeMB = [math]::Round($drive.AvailableFreeSpace / 1MB, 1)
            Write-Host ("Klaar. Vrije ruimte is nu {0} MB." -f $freeMB) -ForegroundColor Green
            if ($freeMB -lt $MinimumFreeMB) {
                Write-Warning 'Nog steeds te weinig ruimte. Zie README.md (stap 3 en 4).'
                $exitCode = 2
            }
            else {
                Write-Host 'Start de Windows 11-upgrade opnieuw.' -ForegroundColor Green
                $exitCode = 0
            }
        }
    }
}
finally {
    if ($mounted) {
        & mountvol.exe "${letter}:" /d | Out-Null
    }
}

exit $exitCode
