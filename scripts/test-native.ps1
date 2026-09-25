param(
    [Parameter(Mandatory = $true)][string]$LuaExe,
    [Parameter(Mandatory = $true)][string]$LuacExe,
    [string]$PackagePath
)
$ErrorActionPreference = 'Stop'
$repoPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifest = Get-Content -LiteralPath (Join-Path $repoPath 'mfile') -Raw | ConvertFrom-Json
Push-Location $repoPath
try {
    $luaFiles = Get-ChildItem -LiteralPath @('src', 'tests', 'examples') -Recurse -File -Filter '*.lua'
    foreach ($file in $luaFiles) {
        & $LuacExe -p $file.FullName
        if ($LASTEXITCODE -ne 0) { throw "Lua syntax failed: $($file.FullName)" }
    }
    Write-Output "SYNTAX=$($luaFiles.Count) passed"
    $jsonFiles = @(Get-ChildItem -LiteralPath @('src', 'tests', 'examples') -Recurse -File -Filter '*.json') + @(Get-Item mfile)
    foreach ($file in $jsonFiles) { Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json | Out-Null }
    Write-Output "METADATA=$($jsonFiles.Count) passed"
    $tradeTriggers = Get-Content src/triggers/commodities/triggers.json -Raw | ConvertFrom-Json
    $buyPattern = ($tradeTriggers | Where-Object name -eq 'buy_success').patterns[0].pattern
    if ('75 tons of Artifacts have been purchased at a cost of 44,700ig and loaded onto your ship.' -notmatch $buyPattern `
        -or $Matches[1] -ne 'Artifacts' -or $Matches[2] -ne '44,700') {
        throw 'Purchase trigger must capture commodity and actual receipt cost'
    }
    $restrictionPattern = ($tradeTriggers | Where-Object name -eq 'sell_error_restricted').patterns[0].pattern
    $salePattern = ($tradeTriggers | Where-Object name -eq 'sell_success').patterns[0].pattern
    foreach ($saleLine in @(
        '75 tons of Libraries sold for 49425ig from your ship',
        '75 tons of Libraries sold for 49,425ig from your ship.',
        '75 tons of Libraries sold to the exchange for 49425ig from your ship',
        '75 tons of Libraries sold to the exchange for 49,425ig',
        '75 tons of Libraries sold for 49425ig'
    )) {
        if ($saleLine -notmatch $salePattern -or $Matches[1] -ne 'Libraries' `
            -or ($Matches[2] -replace ',', '') -ne '49425') {
            throw "Sale trigger missed receipt or captured wrong values: $saleLine"
        }
    }
    foreach ($otherLine in @(
        "This exchange isn't currently buying Libraries.",
        "You don't have any imported Libraries to sell.",
        '75 tons of Libraries have been purchased at a cost of 49425ig and loaded onto your ship.',
        'Someone says: 75 tons of Libraries sold for 49425ig from your ship',
        '75 tons of Libraries sold for 49425ig from your ship [not a receipt]'
    )) {
        if ($otherLine -match $salePattern) { throw "Sale trigger matched unrelated output: $otherLine" }
    }
    $customsPattern = ($tradeTriggers | Where-Object name -eq 'sell_customs').patterns[0].pattern
    $continuationPattern = ($tradeTriggers | Where-Object name -eq 'sell_customs_continuation').patterns[0].pattern
    if ('The Candy cartel deducts 11,430ig customs from the 49,425ig sale proceeds, leaving 37,995ig net.' -notmatch $customsPattern) {
        throw 'Customs trigger missed the reported live notice'
    }
    # Server wraps on spaces: every possible split after the identifying prefix
    # must be capturable, including currency-first and net-only continuations.
    $customsTokens = '11,430ig customs from the 49,425ig sale proceeds, leaving 37,995ig net.'.Split(' ')
    for ($split = 1; $split -lt $customsTokens.Count; $split++) {
        $first = 'The Candy cartel deducts ' + ($customsTokens[0..($split-1)] -join ' ')
        $rest = $customsTokens[$split..($customsTokens.Count-1)] -join ' '
        if ($first -notmatch $customsPattern -or $rest -notmatch $continuationPattern) {
            throw "Customs trigger missed wrapped continuation: $rest"
        }
    }
    Write-Output 'TRADE_PATTERNS=live and legacy sale/customs responses passed'
    foreach ($line in @(
        'This exchange is currently restricted from non-deficit commodity sales by order of the Galactic Administration.',
        'This exchange is currently restricted from non-deficit commodity sales by order of the Galactic',
        'This exchange is currently restricted from non-deficit commodity sales'
    )) {
        if ($line -notmatch $restrictionPattern) { throw 'Restriction trigger missed a full/wrapped response' }
    }
    if ('This exchange is open.' -match $restrictionPattern) { throw 'Restriction trigger is too broad' }

    function Invoke-Suites([string]$SourceRoot) {
        $commands = @(
            @('tests/api/company_run.lua', $SourceRoot),
            @('tests/api/run.lua', "$SourceRoot/src/scripts/api/v1.lua"),
            @('tests/api/native_adapter_run.lua', "$SourceRoot/src/scripts/api/v1.lua", "$SourceRoot/src/scripts/api/adapter.lua"),
            @('tests/exchange_walker/run.lua', $SourceRoot),
            @('tests/commodities/bulk_counted_run.lua', $SourceRoot),
            @('tests/commodities/catalog_run.lua', $SourceRoot),
            @('tests/hauling/customs_policy_run.lua', $SourceRoot),
            @('tests/hauling/refusal_run.lua', $SourceRoot),
            @('tests/hauling/rotation_run.lua', $SourceRoot),
            @('tests/hauling/teleport_run.lua', $SourceRoot),
            @('tests/hauling/navigation_recovery_run.lua', $SourceRoot),
            @('tests/player_db_change_detection_run.lua', $SourceRoot),
            @('tests/who_render_cache_run.lua', $SourceRoot),
            @('tests/table_system_row_refresh_run.lua', $SourceRoot),
            @('tests/stamina/cancel_run.lua', $SourceRoot),
            @('tests/map/startup_topology_sync_run.lua', "$SourceRoot/src/scripts/map/events.lua"),
            @('tests/map/topology_capture_safety_run.lua', "$SourceRoot/src/scripts/map/topology_capture.lua"),
            @('tests/map/content_lifecycle_run.lua', "$SourceRoot/src/scripts/ui/content/map.lua"),
            @('tests/map/galaxy_capture_lifecycle_run.lua', $SourceRoot),
            @('tests/map/explore_orbit_direction_run.lua',
                "$SourceRoot/src/scripts/map/explore_frontier.lua",
                "$SourceRoot/src/scripts/map/explore_system_helpers.lua",
                "$SourceRoot/src/scripts/map/explore.lua"),
            @('tests/map/explore_galaxy_full_run.lua',
                "$SourceRoot/src/scripts/map/explore.lua",
                "$SourceRoot/src/scripts/map/explore_system.lua",
                "$SourceRoot/src/scripts/map/explore_cartel.lua",
                "$SourceRoot/src/scripts/map/explore_galaxy.lua"),
            @('tests/map/navigation_resilience_run.lua',
                "$SourceRoot/src/scripts/map/speedwalk.lua",
                "$SourceRoot/src/scripts/map/whereis_capture.lua",
                "$SourceRoot/src/scripts/map/navigate.lua",
                "$SourceRoot/src/scripts/map/exit.lua",
                "$SourceRoot/src/scripts/map/room_query.lua",
                "$SourceRoot/src/scripts/map/import_export.lua")
        )
        foreach ($command in $commands) {
            & $LuaExe @command
            if ($LASTEXITCODE -ne 0) { throw "Suite failed: $($command[0])" }
        }
    }
    Invoke-Suites '.'

    if ($PackagePath) {
        # Reconstruct Lua sources from the actual compiled XML, not the stage
        # directory, then run the same regression suite against those bytes.
        $verifyPath = Join-Path $repoPath ('build\package-verify-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $verifyPath | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($PackagePath))
        try {
            $reader = [IO.StreamReader]::new($archive.GetEntry('f2ce-tools.xml').Open())
            try { $document = [xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
            $matched = 0
            foreach ($kind in @('Script', 'Trigger')) {
                $directory = if ($kind -eq 'Script') { 'scripts' } else { 'triggers' }
                foreach ($node in $document.SelectNodes("//$kind")) {
                    $body = $node.SelectSingleNode('script')
                    if (-not $body) { continue }
                    $parts = [Collections.Generic.List[string]]::new()
                    $parts.Add($node.SelectSingleNode('name').InnerText)
                    $parent = $node.ParentNode
                    while ($parent.LocalName -eq $kind -or $parent.LocalName -eq ($kind + 'Group')) {
                        $parts.Insert(0, $parent.SelectSingleNode('name').InnerText)
                        $parent = $parent.ParentNode
                    }
                    $relative = 'src/' + $directory + '/' + ($parts -join '/') + '.lua'
                    if ($relative -match '(^|/)\.\.?(/|$)|:|\\') { throw "Unsafe generated script path $relative" }
                    $original = Join-Path $repoPath $relative
                    if (-not (Test-Path -LiteralPath $original -PathType Leaf)) { throw "Unexpected compiled script $relative" }
                    $text = $body.InnerText.Replace("`r`n", "`n").TrimEnd()
                    $source = [IO.File]::ReadAllText($original).Replace("`r`n", "`n").TrimEnd()
                    $source = $source.Replace('@PKGNAME@', $manifest.package).Replace('__PKGNAME__', $manifest.package)
                    $source = $source.Replace('@VERSION@', $manifest.version).Replace('__VERSION__', $manifest.version)
                    if ($relative -eq 'src/scripts/init.lua') {
                        $url = 'https://github.com/' + $manifest.dependency.repo + '/releases/download/' + $manifest.dependency.version + '/Muxlet.mpackage'
                        $source = $source.Replace('local F2T_REQUIRED_MUXLET = nil', 'local F2T_REQUIRED_MUXLET = "' + $manifest.dependency.version + '"')
                        $source = $source.Replace('local MUXLET_URL = nil', 'local MUXLET_URL = "' + $url + '"')
                    }
                    if ($source -ne $text) {
                        throw "Packaged code differs from tested source: $relative"
                    }
                    if ($relative -match '^src/triggers/commodities/(sell_success|sell_customs|sell_customs_continuation)\.lua$') {
                        $triggerName = $node.SelectSingleNode('name').InnerText
                        $expectedPattern = ($tradeTriggers | Where-Object name -eq $triggerName).patterns[0].pattern
                        $patterns = @($node.SelectNodes('regexCodeList/string'))
                        if ($patterns.Count -ne 1 -or $patterns[0].InnerText -ne $expectedPattern) {
                            throw "Packaged trade regex differs from tested metadata: $triggerName"
                        }
                    }
                    $destination = Join-Path $verifyPath $relative
                    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
                    [IO.File]::WriteAllText($destination, $text, [Text.UTF8Encoding]::new($false))
                    $matched++
                }
            }
            Write-Output "PACKAGED_SCRIPTS=$matched matched (init has the intended dependency injection)"
            $reader = [IO.StreamReader]::new($archive.GetEntry('commodities.json').Open())
            try { $catalogText = $reader.ReadToEnd() } finally { $reader.Dispose() }
            $catalogSource = [IO.File]::ReadAllText((Join-Path $repoPath 'src/resources/commodities.json'))
            if ($catalogText.Replace("`r`n", "`n").TrimEnd() -ne $catalogSource.Replace("`r`n", "`n").TrimEnd()) {
                throw 'Packaged base-price catalog differs from tested source'
            }
            New-Item -ItemType Directory -Path (Join-Path $verifyPath 'src/resources') -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $verifyPath 'src/resources/commodities.json'), $catalogText, [Text.UTF8Encoding]::new($false))
            foreach ($required in @('EXCHANGE-WALKER-LICENSE.txt', 'F2CE-LICENSE.txt', 'full.lua')) {
                if (-not $archive.GetEntry($required)) { throw "Package is missing $required" }
            }
        } finally { $archive.Dispose() }
        Invoke-Suites $verifyPath
        Write-Output "PACKAGE_VERIFIED=$PackagePath"
    }
} finally { Pop-Location }
