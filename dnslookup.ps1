param(
    [switch]$UseDoH,
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
# DNS over HTTPS (Cloudflare JSON API)
# ==========================================
function Get-TxtFromDoH {
    param([string]$Name)

    try {
        $uri = "https://cloudflare-dns.com/dns-query?name=$Name&type=TXT"

        $headers = @{
            Accept = "application/dns-json"
        }

        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop

        if ($response.Answer) {
            $txt = $response.Answer |
                Where-Object { $_.type -eq 16 } |
                ForEach-Object { $_.data.Trim('"') }

            return To-Array $txt
        }
    }
    catch {
        if (-not $Quiet) {
            Write-Warning "DoH query failed: $($_.Exception.Message)"
        }
    }

    return $null
}

# ==========================================
# Pure .NET DNS TXT Query (No nslookup)
# ==========================================
function Get-TxtFromSystemDNS {
    param([string]$Name)

    try {
        # Use Resolve-DnsName if Windows
        if ($IsWindows -and (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue)) {
            $records = Resolve-DnsName -Name $Name -Type TXT -ErrorAction Stop
            return To-Array ($records.Strings)
        }

        # Cross-platform fallback using dig if available
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

Write-Host "DNS TXT Flag Resolver"
Write-Host "Running on: $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)"
Write-Host ""

while ($true) {

    $input = Read-Host "Enter domain (blank to quit)"
    if ([string]::IsNullOrWhiteSpace($input)) { break }

    $domain = $input.Trim()

    # Query
    if ($UseDoH) {
        $txtRecords = Get-TxtFromDoH $domain
        $source = "DNS-over-HTTPS (Cloudflare)"
    }
    else {
        $txtRecords = Get-TxtFromSystemDNS $domain
        $source = "System DNS"
    }

    # Normalize type
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
