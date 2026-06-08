[CmdletBinding()]
param(
    [switch]$NoBrowser,
    [switch]$ListQueries,
    [string]$PersonName,
    [string]$ProfileUrl,
    [string]$CompanyName,
    [string]$Website,
    [string]$MatchedSkills,
    [string]$SearchQuery,
    [string]$Notes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$DataDir = Join-Path $ScriptRoot 'Data'
$OutputDir = Join-Path $ScriptRoot 'Output'
$ProfilePath = Join-Path $DataDir 'profile-skills.json'
$StatePath = Join-Path $OutputDir 'state.json'
$WorkbookPath = Join-Path $OutputDir 'LinkedInCompanyTargets.xlsx'

function Ensure-Directories {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

function ConvertTo-XmlText {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Security.SecurityElement]::Escape($Value)
}

function Normalize-Website {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }

    $candidate = $Value.Trim().ToLowerInvariant()
    if ($candidate -notmatch '^[a-z][a-z0-9+\-.]*://') {
        $candidate = "https://$candidate"
    }

    try {
        $uri = [Uri]$candidate
        $host = $uri.Host.ToLowerInvariant()
        if ($host.StartsWith('www.')) {
            $host = $host.Substring(4)
        }
        return $host.TrimEnd('/')
    }
    catch {
        $fallback = $Value.Trim().ToLowerInvariant()
        $fallback = $fallback -replace '^[a-z][a-z0-9+\-.]*://', ''
        $fallback = $fallback -replace '^www\.', ''
        $fallback = ($fallback -split '/')[0]
        return $fallback.TrimEnd('/')
    }
}

function Normalize-CompanyName {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }

    $normalized = $Value.Trim().ToLowerInvariant()
    $normalized = $normalized -replace '\b(s\.?r\.?l\.?|s\.?p\.?a\.?|ltd\.?|limited|inc\.?|gmbh|sas|snc)\b', ''
    $normalized = $normalized -replace '[^a-z0-9]+', ''
    return $normalized
}

function Split-MultiValue {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return @(
        $Value -split ';' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
}

function Join-UniqueValues {
    param(
        [AllowNull()][string]$Existing,
        [AllowNull()][string]$Incoming
    )

    $items = [System.Collections.Generic.List[string]]::new()
    $allItems = @()
    $allItems += @(Split-MultiValue $Existing)
    $allItems += @(Split-MultiValue $Incoming)

    foreach ($item in $allItems) {
        $alreadyPresent = $false
        foreach ($current in $items) {
            if ($current.Equals($item, [System.StringComparison]::OrdinalIgnoreCase)) {
                $alreadyPresent = $true
                break
            }
        }

        if (-not $alreadyPresent) {
            $items.Add($item)
        }
    }

    return ($items -join '; ')
}

function New-EmptyState {
    [pscustomobject]@{
        version = 1
        generatedAt = (Get-Date).ToString('o')
        companies = @()
    }
}

function Read-State {
    if (-not (Test-Path $StatePath)) {
        return New-EmptyState
    }

    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    if ($null -eq $state.companies) {
        $state | Add-Member -NotePropertyName companies -NotePropertyValue @()
    }
    return $state
}

function Save-State {
    param([pscustomobject]$State)

    $State.generatedAt = (Get-Date).ToString('o')
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

function Get-DedupKey {
    param(
        [AllowNull()][string]$CompanyName,
        [AllowNull()][string]$Website
    )

    $normalizedWebsite = Normalize-Website $Website
    if ($normalizedWebsite) {
        return "web:$normalizedWebsite"
    }

    $normalizedCompany = Normalize-CompanyName $CompanyName
    if ($normalizedCompany) {
        return "name:$normalizedCompany"
    }

    throw 'CompanyName o Website sono obbligatori per deduplicare il risultato.'
}

function Find-ExistingCompany {
    param(
        [object[]]$Companies,
        [string]$CompanyName,
        [string]$Website
    )

    $incomingWebsite = Normalize-Website $Website
    $incomingCompany = Normalize-CompanyName $CompanyName
    $incomingKey = Get-DedupKey -CompanyName $CompanyName -Website $Website

    foreach ($company in $Companies) {
        if ($company.DedupKey -eq $incomingKey) {
            return $company
        }

        if ($incomingWebsite -and $company.NormalizedWebsite -eq $incomingWebsite) {
            return $company
        }

        if ($incomingCompany -and $company.NormalizedCompanyName -eq $incomingCompany) {
            return $company
        }
    }

    return $null
}

function Add-OrUpdateCompany {
    param(
        [pscustomobject]$State,
        [string]$PersonName,
        [string]$ProfileUrl,
        [string]$CompanyName,
        [string]$Website,
        [string]$MatchedSkills,
        [string]$SearchQuery,
        [string]$Notes
    )

    if ([string]::IsNullOrWhiteSpace($CompanyName) -and [string]::IsNullOrWhiteSpace($Website)) {
        throw 'Inserire almeno CompanyName o Website.'
    }

    $now = (Get-Date).ToString('s')
    $normalizedWebsite = Normalize-Website $Website
    $normalizedCompany = Normalize-CompanyName $CompanyName
    $existing = Find-ExistingCompany -Companies @($State.companies) -CompanyName $CompanyName -Website $Website

    if ($null -eq $existing) {
        $record = [pscustomobject]@{
            DedupKey = Get-DedupKey -CompanyName $CompanyName -Website $Website
            NormalizedCompanyName = $normalizedCompany
            NormalizedWebsite = $normalizedWebsite
            CompanyName = $CompanyName.Trim()
            Website = $Website.Trim()
            SourcePersonName = $PersonName.Trim()
            SourceProfileUrl = $ProfileUrl.Trim()
            MatchedSkills = $MatchedSkills.Trim()
            SearchQuery = $SearchQuery.Trim()
            Notes = $Notes.Trim()
            FirstSeenAt = $now
            LastSeenAt = $now
        }

        $State.companies = @($State.companies) + $record
        return [pscustomobject]@{ Action = 'Added'; Record = $record }
    }

    if ([string]::IsNullOrWhiteSpace($existing.CompanyName) -and -not [string]::IsNullOrWhiteSpace($CompanyName)) {
        $existing.CompanyName = $CompanyName.Trim()
    }
    if ([string]::IsNullOrWhiteSpace($existing.Website) -and -not [string]::IsNullOrWhiteSpace($Website)) {
        $existing.Website = $Website.Trim()
        $existing.NormalizedWebsite = $normalizedWebsite
        $existing.DedupKey = Get-DedupKey -CompanyName $existing.CompanyName -Website $existing.Website
    }

    $existing.NormalizedCompanyName = Normalize-CompanyName $existing.CompanyName
    $existing.SourcePersonName = Join-UniqueValues $existing.SourcePersonName $PersonName
    $existing.SourceProfileUrl = Join-UniqueValues $existing.SourceProfileUrl $ProfileUrl
    $existing.MatchedSkills = Join-UniqueValues $existing.MatchedSkills $MatchedSkills
    $existing.SearchQuery = Join-UniqueValues $existing.SearchQuery $SearchQuery
    $existing.Notes = Join-UniqueValues $existing.Notes $Notes
    $existing.LastSeenAt = $now

    return [pscustomobject]@{ Action = 'Updated'; Record = $existing }
}

function Read-Profile {
    if (-not (Test-Path $ProfilePath)) {
        throw "File profilo non trovato: $ProfilePath"
    }

    return Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
}

function Get-SearchQueries {
    param([pscustomobject]$Profile)

    foreach ($query in $Profile.queries) {
        $parts = @('site:linkedin.com/in') + @($query.terms | ForEach-Object { '"' + $_ + '"' })
        $queryText = $parts -join ' '
        $encoded = [System.Uri]::EscapeDataString($queryText)

        [pscustomobject]@{
            Category = $query.category
            Priority = $query.priority
            Query = $queryText
            Url = "https://www.google.com/search?q=$encoded"
        }
    }
}

function Export-SearchQueriesCsv {
    param([object[]]$Queries)

    $path = Join-Path $OutputDir 'search-queries.csv'
    $Queries | Sort-Object Priority, Category | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
    return $path
}

function ConvertTo-ColumnName {
    param([int]$Number)

    $name = ''
    while ($Number -gt 0) {
        $mod = ($Number - 1) % 26
        $name = [char](65 + $mod) + $name
        $Number = [math]::Floor(($Number - $mod) / 26)
    }
    return $name
}

function New-InlineStringCell {
    param(
        [int]$Column,
        [int]$Row,
        [AllowNull()][string]$Value
    )

    $cellRef = "$(ConvertTo-ColumnName $Column)$Row"
    $text = ConvertTo-XmlText $Value
    return "<c r=`"$cellRef`" t=`"inlineStr`"><is><t>$text</t></is></c>"
}

function Export-Xlsx {
    param(
        [object[]]$Companies,
        [string]$Path
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $headers = @(
        'CompanyName',
        'Website',
        'SourcePersonName',
        'SourceProfileUrl',
        'MatchedSkills',
        'SearchQuery',
        'Notes',
        'FirstSeenAt',
        'LastSeenAt'
    )

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("linkedin-company-targets-" + [Guid]::NewGuid().ToString('N'))
    $xlDir = Join-Path $tempRoot 'xl'
    $worksheetsDir = Join-Path $xlDir 'worksheets'
    $relsDir = Join-Path $tempRoot '_rels'
    $xlRelsDir = Join-Path $xlDir '_rels'

    New-Item -ItemType Directory -Path $worksheetsDir, $relsDir, $xlRelsDir -Force | Out-Null

    try {
        $contentTypes = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>
'@
        Set-Content -LiteralPath (Join-Path $tempRoot '[Content_Types].xml') -Value $contentTypes -Encoding UTF8

        $rootRels = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
'@
        Set-Content -LiteralPath (Join-Path $relsDir '.rels') -Value $rootRels -Encoding UTF8

        $workbook = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="CompanyTargets" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>
'@
        Set-Content -LiteralPath (Join-Path $xlDir 'workbook.xml') -Value $workbook -Encoding UTF8

        $workbookRels = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>
'@
        Set-Content -LiteralPath (Join-Path $xlRelsDir 'workbook.xml.rels') -Value $workbookRels -Encoding UTF8

        $rows = [System.Collections.Generic.List[string]]::new()
        $headerCells = for ($i = 0; $i -lt $headers.Count; $i++) {
            New-InlineStringCell -Column ($i + 1) -Row 1 -Value $headers[$i]
        }
        $rows.Add("<row r=`"1`">$($headerCells -join '')</row>")

        $rowIndex = 2
        foreach ($company in ($Companies | Sort-Object CompanyName, Website)) {
            $values = @(
                $company.CompanyName,
                $company.Website,
                $company.SourcePersonName,
                $company.SourceProfileUrl,
                $company.MatchedSkills,
                $company.SearchQuery,
                $company.Notes,
                $company.FirstSeenAt,
                $company.LastSeenAt
            )
            $cells = for ($i = 0; $i -lt $values.Count; $i++) {
                New-InlineStringCell -Column ($i + 1) -Row $rowIndex -Value ([string]$values[$i])
            }
            $rows.Add("<row r=`"$rowIndex`">$($cells -join '')</row>")
            $rowIndex++
        }

        $dimensionEndRow = [math]::Max(1, $rowIndex - 1)
        $sheetXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <dimension ref="A1:I$dimensionEndRow"/>
  <sheetViews>
    <sheetView workbookViewId="0">
      <pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>
    </sheetView>
  </sheetViews>
  <sheetData>
$($rows -join "`n")
  </sheetData>
  <autoFilter ref="A1:I$dimensionEndRow"/>
</worksheet>
"@
        Set-Content -LiteralPath (Join-Path $worksheetsDir 'sheet1.xml') -Value $sheetXml -Encoding UTF8

        if (Test-Path $Path) {
            Remove-Item -LiteralPath $Path -Force
        }

        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempRoot, $Path)
    }
    finally {
        if (Test-Path $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

function Prompt-Company {
    param([string]$DefaultSearchQuery)

    Write-Host ''
    Write-Host 'Inserisci un profilo utile trovato. Lascia vuoto il nome azienda per terminare.' -ForegroundColor Cyan
    $company = Read-Host 'Nome azienda'
    if ([string]::IsNullOrWhiteSpace($company)) {
        return $null
    }

    [pscustomobject]@{
        PersonName = Read-Host 'Nome persona trovata'
        ProfileUrl = Read-Host 'URL profilo LinkedIn sorgente'
        CompanyName = $company
        Website = Read-Host 'Sito web azienda'
        MatchedSkills = Read-Host 'Skill rilevate, separate da ;'
        SearchQuery = if ($DefaultSearchQuery) { $DefaultSearchQuery } else { Read-Host 'Query di ricerca usata' }
        Notes = Read-Host 'Note opzionali'
    }
}

function Invoke-InteractiveFlow {
    param(
        [pscustomobject]$State,
        [object[]]$Queries,
        [switch]$NoBrowser
    )

    foreach ($query in ($Queries | Sort-Object Priority, Category)) {
        Write-Host ''
        Write-Host "[$($query.Category) / P$($query.Priority)] $($query.Query)" -ForegroundColor Yellow
        Write-Host $query.Url

        if (-not $NoBrowser) {
            Start-Process $query.Url
        }

        while ($true) {
            $entry = Prompt-Company -DefaultSearchQuery $query.Query
            if ($null -eq $entry) { break }

            $result = Add-OrUpdateCompany -State $State `
                -PersonName $entry.PersonName `
                -ProfileUrl $entry.ProfileUrl `
                -CompanyName $entry.CompanyName `
                -Website $entry.Website `
                -MatchedSkills $entry.MatchedSkills `
                -SearchQuery $entry.SearchQuery `
                -Notes $entry.Notes

            Save-State -State $State
            Export-Xlsx -Companies @($State.companies) -Path $WorkbookPath
            Write-Host "$($result.Action): $($result.Record.CompanyName)" -ForegroundColor Green
        }
    }
}

$CorePath = Join-Path $ScriptRoot 'SearchWork.Core.ps1'
. $CorePath
Initialize-SearchWork -ProjectRoot $ScriptRoot

Ensure-Directories
$profile = Read-Profile
$queries = @(Get-SearchQueries -Profile $profile)
$queriesCsv = Export-SearchQueriesCsv -Queries $queries
$state = Read-State

if ($ListQueries) {
    $queries | Sort-Object Priority, Category | Format-Table Category, Priority, Query, Url -AutoSize
    Write-Host "Query esportate in: $queriesCsv"
    return
}

$hasNonInteractiveCompany = -not [string]::IsNullOrWhiteSpace($CompanyName) -or -not [string]::IsNullOrWhiteSpace($Website)
if ($hasNonInteractiveCompany) {
    $result = Add-OrUpdateCompany -State $state `
        -PersonName $PersonName `
        -ProfileUrl $ProfileUrl `
        -CompanyName $CompanyName `
        -Website $Website `
        -MatchedSkills $MatchedSkills `
        -SearchQuery $SearchQuery `
        -Notes $Notes

    Save-State -State $state
    Export-Xlsx -Companies @($state.companies) -Path $WorkbookPath
    Write-Host "$($result.Action): $($result.Record.CompanyName)"
    Write-Host "Excel aggiornato: $WorkbookPath"
    return
}

Invoke-InteractiveFlow -State $state -Queries $queries -NoBrowser:$NoBrowser
Save-State -State $state
Export-Xlsx -Companies @($state.companies) -Path $WorkbookPath
Write-Host "Excel aggiornato: $WorkbookPath"
