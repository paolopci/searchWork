Set-StrictMode -Version Latest

$script:SearchWorkRoot = $null
$script:DataDir = $null
$script:OutputDir = $null
$script:ProfilePath = $null
$script:StatePath = $null
$script:QueriesCsvPath = $null
$script:WorkbookPath = $null
$script:DashboardDataPath = $null
$script:BackupDir = $null

function Initialize-SearchWork {
    param([string]$ProjectRoot)

    $script:SearchWorkRoot = $ProjectRoot
    $script:DataDir = Join-Path $ProjectRoot 'Data'
    $script:OutputDir = Join-Path $ProjectRoot 'Output'
    $script:ProfilePath = Join-Path $script:DataDir 'profile-skills.json'
    $script:StatePath = Join-Path $script:OutputDir 'state.json'
    $script:QueriesCsvPath = Join-Path $script:OutputDir 'search-queries.csv'
    $script:WorkbookPath = Join-Path $script:OutputDir 'LinkedInCompanyTargets.xlsx'
    $script:DashboardDataPath = Join-Path $script:OutputDir 'dashboard-data.js'
    $script:BackupDir = Join-Path $script:OutputDir 'backups'

    Ensure-Directories
}

function Ensure-SearchWorkInitialized {
    if (-not $script:SearchWorkRoot) {
        throw 'SearchWork non inizializzato. Chiamare Initialize-SearchWork.'
    }
}

function Ensure-Directories {
    Ensure-SearchWorkInitialized
    New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:OutputDir -Force | Out-Null
}

function New-Backup {
    param(
        [string]$Path,
        [string]$Prefix
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $script:BackupDir "$Prefix-$timestamp.json"
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    return $backupPath
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

function New-StableId {
    param(
        [AllowNull()][string]$Prefix,
        [AllowNull()][string]$Seed
    )

    $source = if ([string]::IsNullOrWhiteSpace($Seed)) { [Guid]::NewGuid().ToString('N') } else { $Seed.Trim().ToLowerInvariant() }
    $slug = $source -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = [Guid]::NewGuid().ToString('N')
    }
    if ($Prefix) {
        return "$Prefix-$slug"
    }
    return $slug
}

function Ensure-UniqueId {
    param(
        [string]$BaseId,
        [hashtable]$Seen
    )

    $candidate = $BaseId
    $index = 2
    while ($Seen.ContainsKey($candidate)) {
        $candidate = "$BaseId-$index"
        $index++
    }
    $Seen[$candidate] = $true
    return $candidate
}

function New-EmptyState {
    [pscustomobject]@{
        version = 1
        generatedAt = (Get-Date).ToString('o')
        companies = @()
    }
}

function Ensure-StateSchema {
    param([pscustomobject]$State)

    if ($null -eq $State.PSObject.Properties['companies']) {
        $State | Add-Member -NotePropertyName companies -NotePropertyValue @()
    }

    $seen = @{}
    foreach ($company in @($State.companies)) {
        if ($null -eq $company.PSObject.Properties['Id'] -or [string]::IsNullOrWhiteSpace($company.Id)) {
            $seed = if ($company.DedupKey) { $company.DedupKey } else { "$($company.CompanyName)-$($company.Website)" }
            $company | Add-Member -NotePropertyName Id -NotePropertyValue (Ensure-UniqueId -BaseId (New-StableId -Prefix 'company' -Seed $seed) -Seen $seen)
        }
        else {
            $company.Id = Ensure-UniqueId -BaseId $company.Id -Seen $seen
        }

        if ($null -eq $company.PSObject.Properties['DeletedAt']) {
            $company | Add-Member -NotePropertyName DeletedAt -NotePropertyValue ''
        }
    }

    return $State
}

function Read-State {
    Ensure-SearchWorkInitialized
    if (-not (Test-Path -LiteralPath $script:StatePath)) {
        return New-EmptyState
    }

    $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
    return Ensure-StateSchema -State $state
}

function Save-State {
    param(
        [pscustomobject]$State,
        [switch]$SkipBackup
    )

    Ensure-SearchWorkInitialized
    if (-not $SkipBackup) {
        New-Backup -Path $script:StatePath -Prefix 'state' | Out-Null
    }
    $State = Ensure-StateSchema -State $State
    $State.generatedAt = (Get-Date).ToString('o')
    $State | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:StatePath -Encoding UTF8
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
        if ($company.DeletedAt) {
            continue
        }
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
        [AllowNull()][string]$PersonName,
        [AllowNull()][string]$ProfileUrl,
        [AllowNull()][string]$CompanyName,
        [AllowNull()][string]$Website,
        [AllowNull()][string]$MatchedSkills,
        [AllowNull()][string]$SearchQuery,
        [AllowNull()][string]$Notes
    )

    if ([string]::IsNullOrWhiteSpace($CompanyName) -and [string]::IsNullOrWhiteSpace($Website)) {
        throw 'Inserire almeno CompanyName o Website.'
    }

    $State = Ensure-StateSchema -State $State
    $now = (Get-Date).ToString('s')
    $normalizedWebsite = Normalize-Website $Website
    $normalizedCompany = Normalize-CompanyName $CompanyName
    $existing = Find-ExistingCompany -Companies @($State.companies) -CompanyName $CompanyName -Website $Website

    if ($null -eq $existing) {
        $dedupKey = Get-DedupKey -CompanyName $CompanyName -Website $Website
        $record = [pscustomobject]@{
            Id = New-StableId -Prefix 'company' -Seed $dedupKey
            DedupKey = $dedupKey
            NormalizedCompanyName = $normalizedCompany
            NormalizedWebsite = $normalizedWebsite
            CompanyName = ([string]$CompanyName).Trim()
            Website = ([string]$Website).Trim()
            SourcePersonName = ([string]$PersonName).Trim()
            SourceProfileUrl = ([string]$ProfileUrl).Trim()
            MatchedSkills = ([string]$MatchedSkills).Trim()
            SearchQuery = ([string]$SearchQuery).Trim()
            Notes = ([string]$Notes).Trim()
            FirstSeenAt = $now
            LastSeenAt = $now
            DeletedAt = ''
        }

        $State.companies = @($State.companies) + $record
        Ensure-StateSchema -State $State | Out-Null
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

function Update-CompanyById {
    param(
        [pscustomobject]$State,
        [string]$Id,
        [pscustomobject]$CompanyInput
    )

    $State = Ensure-StateSchema -State $State
    $company = @($State.companies) | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if ($null -eq $company) {
        throw "Azienda non trovata: $Id"
    }
    if ($company.DeletedAt) {
        throw "Azienda eliminata: $Id"
    }
    if ([string]::IsNullOrWhiteSpace($CompanyInput.CompanyName) -and [string]::IsNullOrWhiteSpace($CompanyInput.Website)) {
        throw 'Inserire almeno CompanyName o Website.'
    }

    $company.CompanyName = ([string]$CompanyInput.CompanyName).Trim()
    $company.Website = ([string]$CompanyInput.Website).Trim()
    $company.SourcePersonName = ([string]$CompanyInput.SourcePersonName).Trim()
    $company.SourceProfileUrl = ([string]$CompanyInput.SourceProfileUrl).Trim()
    $company.MatchedSkills = ([string]$CompanyInput.MatchedSkills).Trim()
    $company.SearchQuery = ([string]$CompanyInput.SearchQuery).Trim()
    $company.Notes = ([string]$CompanyInput.Notes).Trim()
    $company.NormalizedWebsite = Normalize-Website $company.Website
    $company.NormalizedCompanyName = Normalize-CompanyName $company.CompanyName
    $company.DedupKey = Get-DedupKey -CompanyName $company.CompanyName -Website $company.Website
    $company.LastSeenAt = (Get-Date).ToString('s')

    return [pscustomobject]@{ Action = 'Updated'; Record = $company }
}

function SoftDelete-Company {
    param(
        [pscustomobject]$State,
        [string]$Id
    )

    $State = Ensure-StateSchema -State $State
    $company = @($State.companies) | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if ($null -eq $company) {
        throw "Azienda non trovata: $Id"
    }

    $company.DeletedAt = (Get-Date).ToString('s')
    $company.LastSeenAt = $company.DeletedAt
    return [pscustomobject]@{ Action = 'Deleted'; Record = $company }
}

function Read-Profile {
    Ensure-SearchWorkInitialized
    if (-not (Test-Path -LiteralPath $script:ProfilePath)) {
        throw "File profilo non trovato: $script:ProfilePath"
    }

    $profile = Get-Content -LiteralPath $script:ProfilePath -Raw | ConvertFrom-Json
    return Ensure-ProfileSchema -Profile $profile
}

function Ensure-ProfileSchema {
    param([pscustomobject]$Profile)

    if ($null -eq $Profile.PSObject.Properties['queries']) {
        $Profile | Add-Member -NotePropertyName queries -NotePropertyValue @()
    }

    $seen = @{}
    foreach ($query in @($Profile.queries)) {
        $seed = "$($query.category)-$(@($query.terms) -join '-')"
        if ($null -eq $query.PSObject.Properties['id'] -or [string]::IsNullOrWhiteSpace($query.id)) {
            $query | Add-Member -NotePropertyName id -NotePropertyValue (Ensure-UniqueId -BaseId (New-StableId -Prefix 'query' -Seed $seed) -Seen $seen)
        }
        else {
            $query.id = Ensure-UniqueId -BaseId $query.id -Seen $seen
        }

        if ($null -eq $query.PSObject.Properties['enabled']) {
            $query | Add-Member -NotePropertyName enabled -NotePropertyValue $true
        }
    }

    return $Profile
}

function Save-Profile {
    param([pscustomobject]$Profile)

    Ensure-SearchWorkInitialized
    New-Backup -Path $script:ProfilePath -Prefix 'profile-skills' | Out-Null
    $Profile = Ensure-ProfileSchema -Profile $Profile
    $Profile | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:ProfilePath -Encoding UTF8
}

function Get-SearchQueries {
    param([pscustomobject]$Profile)

    $Profile = Ensure-ProfileSchema -Profile $Profile
    foreach ($query in $Profile.queries) {
        if ($query.enabled -eq $false) {
            continue
        }

        $terms = @($query.terms | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
        if ($terms.Count -eq 0) {
            continue
        }

        $parts = @('site:linkedin.com/in') + @($terms | ForEach-Object { '"' + $_ + '"' })
        $queryText = $parts -join ' '
        $encoded = [System.Uri]::EscapeDataString($queryText)

        [pscustomobject]@{
            Id = $query.id
            Category = $query.category
            Priority = $query.priority
            Query = $queryText
            Url = "https://www.google.com/search?q=$encoded"
            Terms = $terms
            Enabled = $true
        }
    }
}

function Export-SearchQueriesCsv {
    param([object[]]$Queries)

    Ensure-SearchWorkInitialized
    $csvRows = @($Queries | Sort-Object Priority, Category | ForEach-Object {
        [pscustomobject]@{
            Category = $_.Category
            Priority = $_.Priority
            Query = $_.Query
            Url = $_.Url
        }
    })
    $csvRows | Export-Csv -LiteralPath $script:QueriesCsvPath -NoTypeInformation -Encoding UTF8
    return $script:QueriesCsvPath
}

function Assert-QueryInput {
    param([pscustomobject]$QueryInput)

    if ([string]::IsNullOrWhiteSpace($QueryInput.category)) {
        throw 'La categoria query e obbligatoria.'
    }
    $priority = 0
    if (-not [int]::TryParse(([string]$QueryInput.priority), [ref]$priority)) {
        throw 'La priorita query deve essere numerica.'
    }
    $terms = @()
    if ($QueryInput.terms -is [array]) {
        $terms = @($QueryInput.terms | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    }
    else {
        $terms = @(Split-MultiValue $QueryInput.terms)
    }
    if ($terms.Count -eq 0) {
        throw 'Inserire almeno un termine query.'
    }

    [pscustomobject]@{
        category = ([string]$QueryInput.category).Trim()
        priority = $priority
        terms = $terms
        enabled = if ($null -eq $QueryInput.PSObject.Properties['enabled']) { $true } else { [bool]$QueryInput.enabled }
    }
}

function Add-Query {
    param(
        [pscustomobject]$Profile,
        [pscustomobject]$QueryInput
    )

    $clean = Assert-QueryInput -QueryInput $QueryInput
    $Profile = Ensure-ProfileSchema -Profile $Profile
    $seen = @{}
    foreach ($existing in @($Profile.queries)) {
        $seen[$existing.id] = $true
    }
    $query = [pscustomobject]@{
        id = Ensure-UniqueId -BaseId (New-StableId -Prefix 'query' -Seed "$($clean.category)-$($clean.terms -join '-')") -Seen $seen
        category = $clean.category
        priority = $clean.priority
        terms = $clean.terms
        enabled = $clean.enabled
    }
    $Profile.queries = @($Profile.queries) + $query
    return [pscustomobject]@{ Action = 'Added'; Record = $query }
}

function Update-Query {
    param(
        [pscustomobject]$Profile,
        [string]$Id,
        [pscustomobject]$QueryInput
    )

    $clean = Assert-QueryInput -QueryInput $QueryInput
    $Profile = Ensure-ProfileSchema -Profile $Profile
    $query = @($Profile.queries) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if ($null -eq $query) {
        throw "Query non trovata: $Id"
    }

    $query.category = $clean.category
    $query.priority = $clean.priority
    $query.terms = $clean.terms
    $query.enabled = $clean.enabled
    return [pscustomobject]@{ Action = 'Updated'; Record = $query }
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
        [string]$Path = $script:WorkbookPath
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

    $activeCompanies = @($Companies | Where-Object { -not $_.DeletedAt })
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
        foreach ($company in ($activeCompanies | Sort-Object CompanyName, Website)) {
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

        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Force
        }

        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempRoot, $Path)
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

function New-DashboardPayload {
    param(
        [pscustomobject]$State,
        [pscustomobject]$Profile
    )

    $queries = @(Get-SearchQueries -Profile $Profile)
    [pscustomobject]@{
        generatedAt = (Get-Date).ToString('o')
        state = $State
        queries = $queries
        profile = [pscustomobject]@{
            profileName = $Profile.profileName
            searchLocale = $Profile.searchLocale
            searchModes = $Profile.searchModes
            skills = $Profile.skills
            queries = @($Profile.queries)
        }
    }
}

function Write-DashboardData {
    param([pscustomobject]$Payload)

    $json = $Payload | ConvertTo-Json -Depth 12
    $content = @"
window.SearchWorkDashboardData = $json;
"@
    Set-Content -LiteralPath $script:DashboardDataPath -Value $content -Encoding UTF8
}

function Save-SearchWorkOutputs {
    param(
        [pscustomobject]$State,
        [pscustomobject]$Profile
    )

    $queries = @(Get-SearchQueries -Profile $Profile)
    Export-SearchQueriesCsv -Queries $queries | Out-Null
    Export-Xlsx -Companies @($State.companies) -Path $script:WorkbookPath
    $payload = New-DashboardPayload -State $State -Profile $Profile
    Write-DashboardData -Payload $payload
    return $payload
}
