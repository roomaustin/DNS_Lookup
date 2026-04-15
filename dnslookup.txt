# ==========================================
# Company: 0DLLC
# Script: DNS TXT Flag Resolver
# Author: 0DLLC
# Version: 1.0
# Description:
# Resolves DNS TXT records using system DNS,
# extracts the first integer as a flag,
# supports optional registry write and quiet mode.
# ==========================================

param(
    [int]$Default = 0,
    [switch]$SetRegistry,
    [switch]$Quiet
)

# ==========================================
# Helper: Normalize to Array
# ==========================================
function To-Array {
    param($InputObject)

    if ($null -eq $InputObject) { return $null }
    return @($InputObject)
}

# ==========================================
# System DNS TXT Query (Cross-Platform)
# ==========================================
function Get-TxtFromSystemDNS {
    param([string]$Name)

    try {
        # Windows: Resolve-DnsName
        if ($IsWindows -and (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) {
            $records = Resolve-DnsName -Name $Name -Type TXT -ErrorAction Stop
            return To-Array ($records.Strings)
        }

        # macOS / Linux: dig fallback
        if (Get-Command dig -ErrorAction SilentlyContinue) {
            $result = dig +short TXT $Name
            if ($result) {
                $clean = $result | ForEach-Object { $_.Trim('"') }
                return To-Array $clean
            }
        }

    }
    catch {
        if (-not $Quiet) {
            Write-Warning "System DNS query failed: $($_.Exception.Message)"
        }
    }

    return $null
}

# ==========================================
# Extract First Integer From TXT
# ==========================================
function Parse-Flag {
    param($TxtRecords)

    if (-not $TxtRecords) { return $null }

    foreach ($txt in $TxtRecords) {
        if ($txt -match '\d+') {
            return [int]$matches[0]
        }
    }

    return $null
}

# ==========================================
# Windows-Only Registry Write
# ==========================================
function Set-FlagRegistry {
    param([int]$Value)

    if (-not $IsWindows) { return }

    try {
        $RegPath = "HKLM:\Software\DNSFlag"
        $ValueName = "FlagValue"

        if (-not (Test-Path $RegPath)) {
            New-Item $RegPath -Force | Out-Null
        }

        New-ItemProperty -Path $RegPath `
                         -Name $ValueName `
                         -PropertyType DWord `
                         -Value $Value `
                         -Force | Out-Null
    }
    catch {
        Write-Warning "Registry write failed: $($_.Exception.Message)"
    }
}

# ==========================================
# Main Loop
# ==========================================

Write-Host "DNS TXT Flag Resolver (System DNS Only)"
Write-Host "Running on: $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)"
Write-Host ""

while ($true) {

    $input = Read-Host "Enter domain (blank to quit)"
    if ([string]::IsNullOrWhiteSpace($input)) { break }

    $domain = $input.Trim()

    # Query system DNS only
    $txtRecords = Get-TxtFromSystemDNS $domain
    $source = "System DNS"

    # Normalize
    $txtRecords = To-Array $txtRecords

    # Parse flag
    $flag = Parse-Flag $txtRecords
    if ($null -eq $flag) { $flag = $Default }

    # Optional registry write
    if ($SetRegistry) {
        Set-FlagRegistry $flag
    }

    # Output
    if ($Quiet) {
        Write-Output $flag
    }
    else {
        Write-Host ""
        Write-Host "Domain : $domain"
        Write-Host "Source : $source"

        if ($txtRecords) {
            Write-Host ("TXT    : {0}" -f ($txtRecords -join " | "))
        }
        else {
            Write-Host "TXT    : (none; using Default)"
        }

        Write-Host "Result : $flag"
        Write-Host ""
    }
}

Write-Host "Exited."
