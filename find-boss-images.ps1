# Define JSON files
$JsonFiles = @("1.json", "2.json")

# Function to get Boss ID from WowDB PTR (with fuzzy search backup)
Function Get-BossIdFromWowDB {
    param(
        [string]$BossName
    )

    Write-Host "`n🔎 Searching WowDB PTR for boss: $BossName"

    # Format the search URL for WowDB PTR (Exact Search)
    $SearchUrl = "https://ptr.wowdb.com/npcs?filter-search=$($BossName -replace ' ', '%20')"
    Write-Host "🔗 WowDB search URL: $SearchUrl"

    # Fetch WowDB search page
    Try {
        $Response = Invoke-WebRequest -Uri $SearchUrl -UseBasicParsing
        $HtmlContent = $Response.Content
    } Catch {
        Write-Host "❌ Failed to fetch WowDB search results for: $BossName"
        return $null
    }

    # Extract the first NPC ID from the WowDB search results
    $BossIdMatch = $HtmlContent | Select-String -Pattern 'href="https://ptr.wowdb.com/npcs/(\d+)-[^"]+"' | Select-Object -First 1

    # If Boss ID is found, return it
    If ($BossIdMatch) {
        $BossId = $BossIdMatch.Matches.Groups[1].Value
        Write-Host "✅ Found Boss ID: $BossId"
        return $BossId
    } Else {
        Write-Host "⚠ No exact match found. Trying fuzzy search..."

        # Fuzzy Search: Use first 2 letters of Boss Name
        $FuzzyName = $BossName.Substring(0, [math]::Min(2, $BossName.Length))
        $FuzzySearchUrl = "https://ptr.wowdb.com/npcs?filter-search=$FuzzyName"
        Write-Host "🔗 WowDB Fuzzy Search URL: $FuzzySearchUrl"

        Try {
            $FuzzyResponse = Invoke-WebRequest -Uri $FuzzySearchUrl -UseBasicParsing
            $FuzzyHtmlContent = $FuzzyResponse.Content
        } Catch {
            Write-Host "❌ Failed to fetch WowDB fuzzy search results."
            return $null
        }

        # Extract NPC ID from fuzzy search results
        $FuzzyBossIdMatch = $FuzzyHtmlContent | Select-String -Pattern 'href="https://ptr.wowdb.com/npcs/(\d+)-[^"]+"' | Select-Object -First 1

        If ($FuzzyBossIdMatch) {
            $FuzzyBossId = $FuzzyBossIdMatch.Matches.Groups[1].Value
            Write-Host "✅ Found Boss ID via fuzzy search: $FuzzyBossId"
            return $FuzzyBossId
        } Else {
            Write-Host "❌ No Boss ID found even with fuzzy search."
            return $null
        }
    }
}

# Function to get the Wowhead boss image URL using the Boss ID
Function Get-WowheadImageUrl {
    param(
        [string]$BossId,
        [string]$BossName
    )

    If (-not $BossId) {
        Write-Host "❌ No Boss ID available for: $BossName"
        return $null
    }

    # Construct Wowhead PTR NPC page URL
    $FullBossPageUrl = "https://www.wowhead.com/ptr-2/npc=$BossId"
    Write-Host "🔗 Wowhead NPC Page: $FullBossPageUrl"

    # Fetch the boss's individual page
    Try {
        $BossPageResponse = Invoke-WebRequest -Uri $FullBossPageUrl -UseBasicParsing
        $BossPageContent = $BossPageResponse.Content
    } Catch {
        Write-Host "❌ Failed to fetch boss page: $FullBossPageUrl"
        return $null
    }

    # Extract the image from <meta property="twitter:image">
    $ImageUrlMatch = $BossPageContent | Select-String -Pattern '<meta property="twitter:image" content="(https://wow.zamimg.com/uploads/screenshots/normal/[^"]+)"' | Select-Object -First 1

    If ($ImageUrlMatch) {
        $ImageUrl = $ImageUrlMatch.Matches.Groups[1].Value
        Write-Host "✔ Found image: $ImageUrl"
        return $ImageUrl
    } Else {
        Write-Host "❌ No image found in meta tag!"
        return $null
    }
}

# Process each JSON file
ForEach ($JsonFile in $JsonFiles) {
    If (!(Test-Path $JsonFile)) {
        Write-Host "⚠ JSON file not found: $JsonFile"
        Continue
    }

    Write-Host "`n📂 Processing file: $JsonFile"

    # Read the JSON file
    $Dungeons = Get-Content $JsonFile | ConvertFrom-Json

    # Updated JSON structure
    $UpdatedDungeons = @{}

    # Loop through dungeons and bosses
    ForEach ($Dungeon in $Dungeons.PSObject.Properties) {
        $DungeonName = $Dungeon.Name
        $UpdatedDungeons[$DungeonName] = @{}

        ForEach ($Boss in $Dungeon.Value.PSObject.Properties) {
            $BossName = $Boss.Name
            $BossId = Get-BossIdFromWowDB -BossName $BossName
            $ImageUrl = Get-WowheadImageUrl -BossId $BossId -BossName $BossName

            # Update JSON with the new image URL
            $UpdatedDungeons[$DungeonName][$BossName] = @{
                "hints" = $Boss.Value.hints
                "image" = $ImageUrl
            }
        }
    }

    # Save the updated JSON file
    $UpdatedJsonFile = "Updated_$JsonFile"
    $UpdatedDungeons | ConvertTo-Json -Depth 3 | Set-Content $UpdatedJsonFile

    Write-Host "✔ Updated JSON saved as $UpdatedJsonFile"
}
