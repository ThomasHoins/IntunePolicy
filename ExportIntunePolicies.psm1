<#
.SYNOPSIS
    Exports Intune device configuration and Settings Catalog policies to various formats (CSV, Excel, HTML, Console).

.DESCRIPTION
    This module connects to Microsoft Graph, retrieves Intune device configuration and Settings Catalog policies,
    and exports the results including assignments and settings to the desired output format.

.PARAMETER OutputFormat
    Specifies the output format: Console, CSV, Excel, or HTML. Default: CSV.

.PARAMETER OutputPath
    Target directory for the export files. Default: Desktop\Intune-Policies.

.PARAMETER Platform
    Optional filter for platform-specific policies. Accepts one or more of: android, androidForWork, ios, macOS, windows.

.EXAMPLE
    Export-IntunePolicies -OutputFormat CSV

.EXAMPLE
    Export-IntunePolicies -OutputFormat Excel -OutputPath "C:\Exports\Intune"


.NOTES
    Author: Thomas Hoins
    Created: 2025-09-11
    Requirements: Microsoft.Graph.Authentication, ImportExcel (optional)
#>
function Export-IntunePolicies {
    [CmdletBinding()]
    param (
        [ValidateSet("Console", "CSV", "Excel", "HTML")]
        [string]$OutputFormat = "CSV",

        [string]$OutputPath = "$env:USERPROFILE\Desktop\Intune-Policies",

        [ValidateSet("android", "androidForWork", "ios", "macOS", "windows")]
        #[string[]]$Platform = @()
        [string]$Platform = "windows"
    )

    # Ensure output directory exists
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory | Out-Null
    }

    # Load required modules
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication )) {
        Write-Host "Installing Microsoft.Graph.Authentication Module..."
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
    }
    Import-Module Microsoft.Graph.Authentication

    if ($OutputFormat -eq "Excel" -or $OutputFormat -eq "HTML") {
        if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
            Write-Host "Installing ImportExcel Module..."
            Install-Module ImportExcel -Scope CurrentUser -Force
        }
        Import-Module ImportExcel
    }

    # Create group cache to avoid repeated API calls
    $groupCache = @{}

    # Function to get group name with caching
    function Get-GroupNameCached {
        param ([string]$GroupId)
        if ($groupCache.ContainsKey($GroupId)) {
            return $groupCache[$GroupId]
        }
        try {
            $groupUri = "https://graph.microsoft.com/v1.0/groups/$GroupId"
            $group = Invoke-MgGraphRequest -Uri $groupUri -Method GET -ErrorAction Stop
            if ($group -and $group.displayName) {
                $groupCache[$GroupId] = $group.displayName
                return $group.displayName
            }
            $groupCache[$GroupId] = "Unknown Group ($GroupId)"
            return "Unknown Group ($GroupId)"
        } catch {
            $groupCache[$GroupId] = "Unknown Group ($GroupId)"
            return "Unknown Group ($GroupId)"
        }
    }

    # Function to get assigned groups for a policy
    function Get-AssignedGroups {
        param (
            [string]$PolicyId,
            [string]$PolicyType = "deviceConfigurations"
        )

        if ($PolicyType -and $PolicyType -like '*configurationPolicy*') {
            $assignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$PolicyId/assignments"
        } else {
            $assignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$PolicyId/assignments"
        }

        try {
            $assignments = Invoke-MgGraphRequest -Uri $assignmentsUri -Method GET -ErrorAction Stop
        } catch {
            Write-Verbose "Unable to retrieve assignments for $PolicyType policy $($PolicyId): $($_.Exception.Message)"
            return ""
        }

        $groupNames = @()
        if ($assignments -and $assignments.value) {
            foreach ($assignment in $assignments.value) {
                Write-Debug "Getting group for assignment: $($assignment.id)"
                $targetGroupId = $assignment.target.groupId
                if ($targetGroupId) {
                    $groupNames += Get-GroupNameCached -GroupId $targetGroupId
                }
            }
        }
        return ($groupNames -join ", ")
    }

    # Function to retrieve Custom Configuration Settings
    function Get-CustomConfigurationSettings {
        param ($policy)
        $settings = @()
        $AssignedGroups = Get-AssignedGroups -PolicyId $policy.id -PolicyType $policy.'@odata.type'
        foreach ($setting in $policy.omaSettings) {
            $settings += [PSCustomObject]@{
                PolicyName = $policy.displayName
                Version = $policy.version
                Description = $policy.description
                LastModifiedDateTime = $policy.lastModifiedDateTime
                CreatedDateTime = $policy.createdDateTime
                SettingName = $setting.displayName
                SettingDescription = $setting.description
                SettingType = ($setting.'@odata.type').Split('.')[-1]
                OMAUri = $setting.omaUri
                Value = $setting.value
                AssignedGroups = $AssignedGroups
            }
        }
        return $settings
    }

    # Function to retrieve Generic Configuration Settings
    function Get-GenericConfigurationSettings {
        param ($policy)
        $settings = @()
        $excludedProps = @(
            "displayName", "version", "description", "lastModifiedDateTime", "createdDateTime",
            "id", "@odata.context", "@odata.type", "@microsoft.graph.tips", "roleScopeTagIds",
            "supportsScopeTags", "deviceManagementApplicabilityRuleOsEdition",
            "deviceManagementApplicabilityRuleOsVersion", "deviceManagementApplicabilityRuleDeviceMode"
        )
        $AssignedGroups = Get-AssignedGroups -PolicyId $policy.id -PolicyType $policy.'@odata.type'
        foreach ($property in $policy.GetEnumerator()) {
            if ($excludedProps -notcontains $property.Key -and $null -ne $property.Value) {
                $value = $property.Value
                if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                    $value = $value -join ", "
                }
                $settings += [PSCustomObject]@{
                    PolicyName = $policy.displayName
                    Version = $policy.version
                    Description = $policy.description
                    LastModifiedDateTime = $policy.lastModifiedDateTime
                    CreatedDateTime = $policy.createdDateTime
                    SettingName = $property.Key
                    SettingValue = $value
                    AssignedGroups = $AssignedGroups
                }
            }
        }
        return $settings
    }

    # Function to retrieve Settings Catalog Settings
    function Get-SettingsCatalogSettings {
        param ($policy)
        $settings = @()
        $settingsUri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policy.id)/settings"
        $response = Get-GraphCollection -Uri $settingsUri
        if (-not $response -or $response.Count -eq 0) {
            return $settings
        }

        $AssignedGroups = Get-AssignedGroups -PolicyId $policy.id -PolicyType $policy.'@odata.type'
        foreach ($setting in $response) {
            if (-not $setting.settingInstance) {
                continue
            }

            $Children = ""
            $choiceValue = $setting.settingInstance.choiceSettingValue
            
            if ($choiceValue -and $choiceValue.children) {
                $childrenArray = @()
                foreach ($child in $choiceValue.children) {
                    if ($child.choiceSettingValue.value) {
                        $childrenArray += "$($child.settingDefinitionId): $($child.choiceSettingValue.value.Split("_")[-1])"
                    } elseif ($child.simpleSettingValue) {
                        $childrenArray += "$($child.settingDefinitionId): $($child.simpleSettingValue.value)"
                    } else {
                        $childrenArray += "$($child.settingDefinitionId): Not Set"
                    }
                }
                $Children = $childrenArray -join "; "
            }

            $Value = if ($choiceValue.value) { 
                $choiceValue.value.Split("_")[-1] 
            } else { 
                "Not Set" 
            }

            $settings += [PSCustomObject]@{
                PolicyName          = $policy.name
                Description         = $policy.description
                LastModifiedDateTime= $policy.lastModifiedDateTime
                CreatedDateTime     = $policy.createdDateTime
                AssignedGroups      = $AssignedGroups
                SettingName         = $setting.settingInstance.settingDefinitionId
                Value               = $Value
                Children            = $Children
            }
        }
        return $settings
    }

    function Save-HtmlReport {
        param (
            [hashtable]$GroupedPolicies,
            [string]$OutputPath
        )

        $reportFile = Join-Path $OutputPath "Intune-Policies.html"
        $tabs = @()
        $sections = @()

        foreach ($groupName in $GroupedPolicies.Keys) {
            $tabId = [regex]::Replace($groupName, '[^a-zA-Z0-9]', '_')
            $tabs += [PSCustomObject]@{ GroupName = $groupName; TabId = $tabId }

            $sectionHtml = "<div id='$tabId' class='tab-content'>"
            $sectionHtml += "<h1>$groupName</h1>"

            if (-not $GroupedPolicies[$groupName] -or $GroupedPolicies[$groupName].Count -eq 0) {
                $sectionHtml += "<p>Keine Richtlinien in dieser Kategorie gefunden.</p>"
            } else {
                $policyGroups = $GroupedPolicies[$groupName] | Group-Object -Property PolicyId, PolicyName, Description, Version, LastModifiedDateTime, CreatedDateTime, AssignedGroups
                foreach ($policyGroup in $policyGroups) {
                    $policy = $policyGroup.Group[0]
                    $sectionHtml += "<div class='policy-block'>"
                    $sectionHtml += "<div class='policy-header'><h2>$($policy.PolicyName)</h2>"
                    if ($policy.Description) {
                        $sectionHtml += "<p class='policy-meta'>$([System.Net.WebUtility]::HtmlEncode($policy.Description))</p>"
                    }
                    $sectionHtml += "<p class='policy-meta'><strong>Version:</strong> $($policy.Version) | <strong>Erstellt:</strong> $($policy.CreatedDateTime) | <strong>Geändert:</strong> $($policy.LastModifiedDateTime)</p>"
                    if ($policy.AssignedGroups) {
                        $sectionHtml += "<p class='policy-meta'><strong>Zugewiesene Gruppen:</strong> $([System.Net.WebUtility]::HtmlEncode($policy.AssignedGroups))</p>"
                    }
                    $sectionHtml += "</div>"

                    $settingProperties = $policyGroup.Group[0].PSObject.Properties | Where-Object {
                        $_.Name -notin @('PolicyId', 'PolicyName', 'Description', 'Version', 'LastModifiedDateTime', 'CreatedDateTime', 'AssignedGroups')
                    } | Select-Object -ExpandProperty Name

                    if ($policyGroup.Group.Count -gt 0 -and $settingProperties.Count -gt 0) {
                        $sectionHtml += "<table class='setting-table'><thead><tr>"
                        foreach ($propName in $settingProperties) {
                            $sectionHtml += "<th>$propName</th>"
                        }
                        $sectionHtml += "</tr></thead><tbody>"

                        foreach ($setting in $policyGroup.Group) {
                            $sectionHtml += "<tr>"
                            foreach ($propName in $settingProperties) {
                                $value = $setting.$propName
                                if ($null -eq $value) { $value = "" }
                                $value = [System.Web.HttpUtility]::HtmlEncode($value.ToString())
                                $sectionHtml += "<td>$value</td>"
                            }
                            $sectionHtml += "</tr>"
                        }
                        $sectionHtml += "</tbody></table>"
                    } else {
                        $sectionHtml += "<p>Keine Einstellungen für diese Richtlinie gefunden.</p>"
                    }

                    $sectionHtml += "</div>"
                }
            }

            $sectionHtml += "</div>"
            $sections += $sectionHtml
        }

        $headerHtml = @"
<!DOCTYPE html>
<html lang='de'>
<head>
    <meta charset='utf-8'>
    <title>Intune Richtlinien Export</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f6f7f8; color: #222; }
        .tabs { display: flex; flex-wrap: wrap; border-bottom: 1px solid #ccc; margin-bottom: 18px; }
        .tab { padding: 12px 18px; cursor: pointer; border: 1px solid #ccc; border-bottom: none; background: #e9ecef; margin-right: 6px; border-top-left-radius: 8px; border-top-right-radius: 8px; }
        .tab.active { background: #fff; font-weight: 700; }
        .tab-content { display: none; padding: 20px; border: 1px solid #ccc; border-radius: 0 8px 8px 8px; background: #fff; }
        .tab-content.active { display: block; }
        .policy-block { border: 1px solid #d6d8db; border-radius: 8px; padding: 18px; margin-bottom: 20px; background: #fbfcfd; }
        .policy-header h2 { margin: 0 0 8px; }
        .policy-meta { margin: 4px 0; color: #4d4d4d; }
        .setting-table { width: 100%; border-collapse: collapse; margin-top: 14px; }
        .setting-table th, .setting-table td { border: 1px solid #dfe2e6; padding: 10px; text-align: left; vertical-align: top; }
        .setting-table th { background: #f2f4f7; }
        .setting-table tbody tr:nth-child(odd) { background: #fcfcfc; }
        .separator { border-top: 1px solid #d1d5db; margin: 22px 0; }
    </style>
</head>
<body>
    <div class='tabs'>
"@
        foreach ($tab in $tabs) {
            $headerHtml += "        <div class='tab' data-target='$($tab.TabId)'>$($tab.GroupName)</div>`r`n"
        }
        $headerHtml += @"
    </div>
"@
        $headerHtml += $sections -join "`r`n"
        $headerHtml += @"
    <script>
        const tabs = document.querySelectorAll('.tab');
        const contents = document.querySelectorAll('.tab-content');
        function activateTab(targetId) {
            tabs.forEach(tab => {
                tab.classList.toggle('active', tab.dataset.target === targetId);
            });
            contents.forEach(content => {
                content.classList.toggle('active', content.id === targetId);
            });
        }
        tabs.forEach(tab => {
            tab.addEventListener('click', () => activateTab(tab.dataset.target));
        });
        if (tabs.length > 0) {
            activateTab(tabs[0].dataset.target);
        }
    </script>
</body>
</html>
"@
        Set-Content -Path $reportFile -Value $headerHtml -Encoding UTF8
    }

    function Get-GraphCollection {
        param (
            [string]$Uri
        )
        $items = @()
        try {
            $response = Invoke-MgGraphRequest -Method GET -Uri $Uri -ErrorAction Stop
        } catch {
            Write-Verbose "Unable to retrieve Graph collection from ${$Uri}: $($_.Exception.Message)"
            return $items
        }

        if ($response.value) {
            $items += $response.value
        }
        while ($response.'@odata.nextLink') {
            try {
                $response = Invoke-MgGraphRequest -Method GET -Uri $response.'@odata.nextLink' -ErrorAction Stop
            } catch {
                Write-Verbose "Unable to retrieve next page from $($response.'@odata.nextLink'): $($_.Exception.Message)"
                break
            }
            if ($response.value) {
                $items += $response.value
            }
        }
        return $items
    }

    function Matches-PlatformFilter {
        param (
            $policy,
            [string[]]$PlatformFilter
        )
        if (-not $PlatformFilter -or $PlatformFilter.Count -eq 0) {
            return $true
        }

        $normalizedFilter = $PlatformFilter | ForEach-Object {
            if ($_ -ne $null) { $_.ToString().Trim().ToLowerInvariant() }
        } | Where-Object { $_ }

        $potentialValues = @()
        foreach ($prop in 'platform', 'platformType', 'platforms') {
            if ($policy.PSObject.Properties.Match($prop)) {
                $potentialValues += $policy.$prop
            }
        }

        $normalizedFilter = $normalizedFilter | ForEach-Object { $_ }
        $isWindowsFilter = $normalizedFilter -contains 'windows'

        if ($policy.'@odata.type') {
            $odataTypeString = $policy.'@odata.type'.ToString().ToLowerInvariant()
            if ($odataTypeString -like '*windows*') {
                $potentialValues += 'windows'
            }
        }

        $actualValues = $potentialValues | ForEach-Object {
            if ($_ -is [System.Collections.IEnumerable] -and -not ($_ -is [string])) {
                $_ | ForEach-Object { $_.ToString().ToLowerInvariant() }
            } elseif ($_ -ne $null) {
                $_.ToString().ToLowerInvariant()
            }
        } | Where-Object { $_ }

        foreach ($value in $actualValues) {
            if ($normalizedFilter -contains $value) {
                return $true
            }
            if ($isWindowsFilter -and $value -like 'windows*') {
                return $true
            }
        }

        return $false
    }

    If (-not (Get-MgContext)) {
        Write-Host "Connecting to Microsoft Graph..."
        Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All"
    }   

    # Retrieve Device Configuration Policies
    Write-Host "Retrieving device configuration policies..."
    $policies = Get-GraphCollection -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"
    Write-Host "Found $($policies.Count) device configuration policies. Processing..."
    $groupedPolicies = @{}

    # Pre-fetch all unique group IDs from assignments for caching
    Write-Host "Pre-fetching group information..."
    $uniqueGroupIds = @()
    foreach ($policy in $policies) {
        try {
            $assignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($policy.id)/assignments"
            $assignments = Invoke-MgGraphRequest -Uri $assignmentsUri -Method GET -ErrorAction Stop
            if ($assignments -and $assignments.value) {
                foreach ($assignment in $assignments.value) {
                    if ($assignment.target.groupId) {
                        $uniqueGroupIds += $assignment.target.groupId
                    }
                }
            }
        } catch {
            Write-Verbose "Skipping assignments for policy ${$policy.id}: $($_.Exception.Message)"
        }
    }
    
    # Remove duplicates and fetch all groups at once
    $uniqueGroupIds = $uniqueGroupIds | Sort-Object -Unique
    foreach ($groupId in $uniqueGroupIds) {
        try {
            $groupUri = "https://graph.microsoft.com/v1.0/groups/$groupId"
            $group = Invoke-MgGraphRequest -Uri $groupUri -Method GET -ErrorAction Stop
            if ($group -and $group.displayName) {
                $groupCache[$groupId] = $group.displayName
            } else {
                $groupCache[$groupId] = "Unknown Group ($groupId)"
            }
        } catch {
            $groupCache[$groupId] = "Unknown Group ($groupId)"
        }
    }
    Write-Host "Cached $($groupCache.Count) groups. Processing policies..."

    # Process policies - sequential to avoid Graph throttling
    foreach ($policy in $policies) {
        if (-not (Matches-PlatformFilter -policy $policy -PlatformFilter $Platform)) {
            continue
        }

        $odataType = ($policy.'@odata.type').Split('.')[-1]
        if (-not $groupedPolicies.ContainsKey($odataType)) {
            $groupedPolicies[$odataType] = @()
        }
        if ($odataType -eq "windows10CustomConfiguration") {
            $settings = Get-CustomConfigurationSettings -policy $policy
        } else {
            $settings = Get-GenericConfigurationSettings -policy $policy
        }
        $groupedPolicies[$odataType] += $settings
    }

    # Retrieve Settings Catalog Policies
    Write-Host "Retrieving Settings Catalog policies..."
    $catalogPolicies = Get-GraphCollection -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
    Write-Host "Found $($catalogPolicies.Count) Settings Catalog policies. Processing..."
    
    if (-not $groupedPolicies.ContainsKey("SettingsCatalog")) {
        $groupedPolicies["SettingsCatalog"] = @()
    }
    
    foreach ($catalogPolicy in $catalogPolicies) {
        if (-not (Matches-PlatformFilter -policy $catalogPolicy -PlatformFilter $Platform)) {
            continue
        }

        $settings = Get-SettingsCatalogSettings -policy $catalogPolicy
        $groupedPolicies["SettingsCatalog"] += $settings
    }

    foreach ($key in $groupedPolicies.Keys) {
            $data = $groupedPolicies[$key]
            switch ($OutputFormat) {
                "Console" {
                    $data | Format-Table -AutoSize
                }
                "CSV" {
                    $data | Export-Csv -Path (Join-Path $OutputPath "$key.csv") -NoTypeInformation -Encoding UTF8
                }
                "Excel" {
                    $data | Export-Excel -Path (Join-Path $OutputPath "Intune-Policies.xlsx") -WorksheetName $key -AutoSize -Append
                }
                "HTML" {
                    # HTML export is handled once for all grouped policy categories
                }
            }
        }

    if ($OutputFormat -eq "HTML") {
        Save-HtmlReport -GroupedPolicies $groupedPolicies -OutputPath $OutputPath
    }

    Write-Host "Export complete: $OutputPath"
}
