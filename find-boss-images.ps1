# Define JSON files
$JsonFiles = @("1.json", "2.json")

# Function to get Boss IDs from WowDB PTR
Function Get-BossIdsFromWowDB {
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

    # Extract all NPC IDs from the WowDB search results
    $BossIdMatches = $HtmlContent | Select-String -Pattern 'href="https://ptr.wowdb.com/npcs/(\d+)-[^"]+"' -AllMatches
    
    # If no Boss IDs are found, return null
    If (-not $BossIdMatches) {
        If ($BossName.Length -ne 2) {
            return Get-BossIdsFromWowDB -BossName $BossName.Substring(0, [math]::Min(2, $BossName.Length))
        }

        Write-Host "❌ No NPC IDs found for: $BossName"
        return $null
    }

    # Extract all Boss IDs
    $BossIds = $BossIdMatches.Matches | ForEach-Object { $_.Groups[1].Value }
    return $BossIds
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
            $BossIds = Get-BossIdsFromWowDB -BossName $BossName

            ForEach ($BossId in $BossIds) {
                $ImageUrl = Get-WowheadImageUrl -BossId $BossId -BossName $BossName
                If ($ImageUrl) {
                    Write-Host "🌟 Boss: $BossName (ID: $BossId) has a screenshot on Wowhead."
                    
                    $UpdatedDungeons[$DungeonName][$BossName] = @{
                        "hints" = $Boss.Value.hints
                        "image" = $ImageUrl
                    }
                    
                    Break # Stop checking after the first valid screenshot
                }
            }
        }
    }

    # Save the updated JSON file
    $UpdatedDungeons | ConvertTo-Json -Depth 3 | Set-Content $JsonFile

    Write-Host "✔ Updated JSON saved as $JsonFile"
}
