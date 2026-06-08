[CmdletBinding()]
param(
    [int]$Port = 8765
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DashboardDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $DashboardDir
$CorePath = Join-Path $ProjectRoot 'SearchWork.Core.ps1'
. $CorePath
Initialize-SearchWork -ProjectRoot $ProjectRoot

$Prefix = "http://127.0.0.1:$Port/"
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($Prefix)

function ConvertTo-JsonResponse {
    param([object]$Value)
    return ($Value | ConvertTo-Json -Depth 12)
}

function Read-RequestJson {
    param([System.Net.HttpListenerRequest]$Request)

    if (-not $Request.HasEntityBody) {
        return [pscustomobject]@{}
    }

    $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
    try {
        $body = $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }

    if ([string]::IsNullOrWhiteSpace($body)) {
        return [pscustomobject]@{}
    }

    return $body | ConvertFrom-Json
}

function Write-Response {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [string]$ContentType,
        [string]$Body
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.ContentEncoding = [System.Text.Encoding]::UTF8
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Write-Json {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [object]$Value
    )

    Write-Response -Response $Response -StatusCode $StatusCode -ContentType 'application/json; charset=utf-8' -Body (ConvertTo-JsonResponse $Value)
}

function Write-ErrorJson {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [string]$Message
    )

    Write-Json -Response $Response -StatusCode $StatusCode -Value ([pscustomobject]@{
        ok = $false
        error = $Message
    })
}

function Get-StaticContentType {
    param([string]$Path)

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.html' { return 'text/html; charset=utf-8' }
        '.js' { return 'application/javascript; charset=utf-8' }
        '.css' { return 'text/css; charset=utf-8' }
        '.json' { return 'application/json; charset=utf-8' }
        '.png' { return 'image/png' }
        '.svg' { return 'image/svg+xml' }
        default { return 'application/octet-stream' }
    }
}

function Resolve-StaticPath {
    param([string]$UrlPath)

    $relative = $UrlPath.TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($relative)) {
        $relative = 'Dashboard/index.html'
    }

    if ($relative -eq 'index.html') {
        $relative = 'Dashboard/index.html'
    }
    elseif ($relative -eq 'app.js') {
        $relative = 'Dashboard/app.js'
    }

    $candidate = Join-Path $ProjectRoot ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $full = [System.IO.Path]::GetFullPath($candidate)
    $dashboardRoot = [System.IO.Path]::GetFullPath($DashboardDir)
    $outputRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'Output'))

    if ($full.StartsWith($dashboardRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith($outputRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full
    }

    return $null
}

function Get-FreshDashboardPayload {
    $state = Read-State
    $profile = Read-Profile
    $payload = Save-SearchWorkOutputs -State $state -Profile $profile
    return $payload
}

function Save-StateAndReturnPayload {
    param([pscustomobject]$State)

    Save-State -State $State
    $profile = Read-Profile
    return Save-SearchWorkOutputs -State $State -Profile $profile
}

function Save-ProfileAndReturnPayload {
    param([pscustomobject]$Profile)

    Save-Profile -Profile $Profile
    $state = Read-State
    return Save-SearchWorkOutputs -State $state -Profile $Profile
}

function Invoke-Api {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response
    )

    $method = $Request.HttpMethod.ToUpperInvariant()
    $path = $Request.Url.AbsolutePath.TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = '/'
    }

    if ($method -eq 'GET' -and $path -eq '/api/dashboard') {
        Write-Json -Response $Response -StatusCode 200 -Value (Get-FreshDashboardPayload)
        return
    }

    if ($method -eq 'POST' -and $path -eq '/api/companies') {
        $input = Read-RequestJson -Request $Request
        $state = Read-State
        $result = Add-OrUpdateCompany -State $state `
            -PersonName $input.SourcePersonName `
            -ProfileUrl $input.SourceProfileUrl `
            -CompanyName $input.CompanyName `
            -Website $input.Website `
            -MatchedSkills $input.MatchedSkills `
            -SearchQuery $input.SearchQuery `
            -Notes $input.Notes
        $payload = Save-StateAndReturnPayload -State $state
        Write-Json -Response $Response -StatusCode 200 -Value ([pscustomobject]@{ ok = $true; result = $result; dashboard = $payload })
        return
    }

    if ($method -eq 'PUT' -and $path -match '^/api/companies/([^/]+)$') {
        $id = [System.Uri]::UnescapeDataString($Matches[1])
        $input = Read-RequestJson -Request $Request
        $state = Read-State
        $result = Update-CompanyById -State $state -Id $id -CompanyInput $input
        $payload = Save-StateAndReturnPayload -State $state
        Write-Json -Response $Response -StatusCode 200 -Value ([pscustomobject]@{ ok = $true; result = $result; dashboard = $payload })
        return
    }

    if ($method -eq 'DELETE' -and $path -match '^/api/companies/([^/]+)$') {
        $id = [System.Uri]::UnescapeDataString($Matches[1])
        $state = Read-State
        $result = SoftDelete-Company -State $state -Id $id
        $payload = Save-StateAndReturnPayload -State $state
        Write-Json -Response $Response -StatusCode 200 -Value ([pscustomobject]@{ ok = $true; result = $result; dashboard = $payload })
        return
    }

    if ($method -eq 'POST' -and $path -eq '/api/queries') {
        $input = Read-RequestJson -Request $Request
        $profile = Read-Profile
        $result = Add-Query -Profile $profile -QueryInput $input
        $payload = Save-ProfileAndReturnPayload -Profile $profile
        Write-Json -Response $Response -StatusCode 200 -Value ([pscustomobject]@{ ok = $true; result = $result; dashboard = $payload })
        return
    }

    if ($method -eq 'PUT' -and $path -match '^/api/queries/([^/]+)$') {
        $id = [System.Uri]::UnescapeDataString($Matches[1])
        $input = Read-RequestJson -Request $Request
        $profile = Read-Profile
        $result = Update-Query -Profile $profile -Id $id -QueryInput $input
        $payload = Save-ProfileAndReturnPayload -Profile $profile
        Write-Json -Response $Response -StatusCode 200 -Value ([pscustomobject]@{ ok = $true; result = $result; dashboard = $payload })
        return
    }

    if ($method -eq 'POST' -and $path -match '^/api/queries/([^/]+)/open$') {
        $id = [System.Uri]::UnescapeDataString($Matches[1])
        $profile = Read-Profile
        $query = @(Get-SearchQueries -Profile $profile) | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if ($null -eq $query) {
            Write-ErrorJson -Response $Response -StatusCode 404 -Message "Query non trovata o disabilitata: $id"
            return
        }
        Start-Process $query.Url
        Write-Json -Response $Response -StatusCode 200 -Value ([pscustomobject]@{ ok = $true; url = $query.Url })
        return
    }

    Write-ErrorJson -Response $Response -StatusCode 404 -Message "Endpoint non trovato: $method $path"
}

Get-FreshDashboardPayload | Out-Null

try {
    $listener.Start()
}
catch {
    throw "Impossibile avviare il server su $Prefix. Dettaglio: $($_.Exception.Message)"
}

Start-Process $Prefix
Write-Host "Dashboard operativa avviata: $Prefix"
Write-Host 'Chiudere questa finestra o premere Ctrl+C per fermare il server.'

try {
    while ($listener.IsListening) {
        $asyncResult = $listener.BeginGetContext($null, $null)
        while ($listener.IsListening -and -not $asyncResult.AsyncWaitHandle.WaitOne(250)) {
        }
        if (-not $listener.IsListening) {
            break
        }
        $context = $listener.EndGetContext($asyncResult)
        try {
            $requestPath = $context.Request.Url.AbsolutePath
            if ($requestPath.StartsWith('/api/', [System.StringComparison]::OrdinalIgnoreCase)) {
                Invoke-Api -Request $context.Request -Response $context.Response
                continue
            }

            $staticPath = Resolve-StaticPath -UrlPath $requestPath
            if (-not $staticPath -or -not (Test-Path -LiteralPath $staticPath)) {
                Write-ErrorJson -Response $context.Response -StatusCode 404 -Message "File non trovato: $requestPath"
                continue
            }

            $bytes = [System.IO.File]::ReadAllBytes($staticPath)
            $context.Response.StatusCode = 200
            $context.Response.ContentType = Get-StaticContentType -Path $staticPath
            $context.Response.ContentLength64 = $bytes.Length
            $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            $context.Response.OutputStream.Close()
        }
        catch {
            if ($context.Response.OutputStream.CanWrite) {
                Write-ErrorJson -Response $context.Response -StatusCode 500 -Message $_.Exception.Message
            }
        }
    }
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
