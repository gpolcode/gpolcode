# Define JSON files
$JsonFiles = @("1.json", "2.json")

# Function to get Boss IDs from WowDB
Function Get-BossIdsFromWowDB {
    param(
        [string]$BossName
    )

    Write-Host "`n🔎 Searching WowDB for boss: $BossName"

    # Format the search URL for WowDB (Exact Search)
    $SearchUrl = "https://wowdb.com/npcs?filter-search=$($BossName -replace ' ', '%20')"
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
    $BossIdMatches = $HtmlContent | Select-String -Pattern 'href="https://wowdb.com/npcs/(\d+)-[^"]+"' -AllMatches
    
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

    # Construct Wowhead NPC page URL
    $FullBossPageUrl = "https://www.wowhead.com/npc=$BossId"
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

    # Loop through dungeons and bosses
    ForEach ($Dungeon in $Dungeons.PSObject.Properties) {
        $DungeonName = $Dungeon.Name

        ForEach ($Boss in $Dungeon.Value.PSObject.Properties) {
            $BossName = $Boss.Name
            $BossId = $Boss.Value.NpcId

            If ($BossId) {
                $ImageUrl = Get-WowheadImageUrl -BossId $BossId -BossName $BossName
                
                If ($ImageUrl) {
                    $Boss.Value.image = $ImageUrl
                }
            } else {
                $BossIds = Get-BossIdsFromWowDB -BossName $BossName

                ForEach ($BossId in $BossIds) {
                    $ImageUrl = Get-WowheadImageUrl -BossId $BossId -BossName $BossName
                    If ($ImageUrl) {
                        Write-Host "🌟 Boss: $BossName (ID: $BossId) has a screenshot on Wowhead."                    
                        $Boss.Value.image = $ImageUrl
                        $Boss.Value | Add-Member -NotePropertyName NpcId -NotePropertyValue $BossId    
                        Break # Stop checking after the first valid screenshot
                    }
                }
            }
        }
    }

    # Save the updated JSON file
    $Dungeons | ConvertTo-Json -Depth 3 | Set-Content $JsonFile

    Write-Host "✔ Updated JSON saved as $JsonFile"
}
