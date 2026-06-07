[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DashboardDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $DashboardDir
$ScriptPath = Join-Path $ProjectRoot 'Search-LinkedInCompanies.ps1'
$OutputDir = Join-Path $ProjectRoot 'Output'
$StatePath = Join-Path $OutputDir 'state.json'
$QueriesPath = Join-Path $OutputDir 'search-queries.csv'
$DashboardDataPath = Join-Path $OutputDir 'dashboard-data.js'
$DashboardIndexPath = Join-Path $DashboardDir 'index.html'

function Read-StateData {
    if (-not (Test-Path -LiteralPath $StatePath)) {
        return [pscustomobject]@{
            version = 1
            generatedAt = $null
            companies = @()
        }
    }

    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    if ($null -eq $state.PSObject.Properties['companies']) {
        $state | Add-Member -NotePropertyName companies -NotePropertyValue @()
    }

    return $state
}

function Read-QueriesData {
    if (-not (Test-Path -LiteralPath $QueriesPath)) {
        return @()
    }

    return @(Import-Csv -LiteralPath $QueriesPath)
}

if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Script principale non trovato: $ScriptPath"
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -NoBrowser -ListQueries | Out-Host

$state = Read-StateData
$queries = Read-QueriesData

$payload = [pscustomobject]@{
    generatedAt = (Get-Date).ToString('o')
    state = $state
    queries = $queries
}

$json = $payload | ConvertTo-Json -Depth 12
$content = @"
window.SearchWorkDashboardData = $json;
"@

Set-Content -LiteralPath $DashboardDataPath -Value $content -Encoding UTF8

if (-not (Test-Path -LiteralPath $DashboardIndexPath)) {
    throw "Dashboard non trovata: $DashboardIndexPath"
}

Start-Process $DashboardIndexPath
Write-Host "Dashboard avviata: $DashboardIndexPath"
Write-Host "Dati dashboard generati: $DashboardDataPath"

