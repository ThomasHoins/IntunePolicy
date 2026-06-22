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
            $group = Invoke-MgGraphRequest -Uri $groupUri -Method GET
            $groupCache[$GroupId] = $group.displayName
            return $group.displayName
        } catch {
            $groupCache[$GroupId] = "Unknown Group ($GroupId)"
            return "Unknown Group ($GroupId)"
        }
    }

    # Function to get assigned groups for a policy
    function Get-AssignedGroups {
        param ([string]$PolicyId)
        $assignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$PolicyId/assignments"
        $assignments = Invoke-MgGraphRequest -Uri $assignmentsUri -Method GET
        $groupNames = @()
        foreach ($assignment in $assignments.value) {
            Write-Debug "Getting group for assignment: $($assignment.id)"
            $targetGroupId = $assignment.target.groupId
            if ($targetGroupId) {
                $groupNames += Get-GroupNameCached -GroupId $targetGroupId
            }
        }
        return ($groupNames -join ", ")
    }

    # Function to retrieve Custom Configuration Settings
    function Get-CustomConfigurationSettings {
        param ($policy)
        $settings = @()
        $AssignedGroups = Get-AssignedGroups -PolicyId $policy.id
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
        $AssignedGroups = Get-AssignedGroups -PolicyId $policy.id
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
                SettingName         = $setting.settingInstance.settingDefinitionId
                Value               = $Value
                Children            = $Children
            }
        }
        return $settings
    }

    function Get-GraphCollection {
        param (
            [string]$Uri
        )
        $items = @()
        $response = Invoke-MgGraphRequest -Method GET -Uri $Uri
        if ($response.value) {
            $items += $response.value
        }
        while ($response.'@odata.nextLink') {
            $response = Invoke-MgGraphRequest -Method GET -Uri $response.'@odata.nextLink'
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
            $assignments = Invoke-MgGraphRequest -Uri $assignmentsUri -Method GET
            foreach ($assignment in $assignments.value) {
                if ($assignment.target.groupId) {
                    $uniqueGroupIds += $assignment.target.groupId
                }
            }
        } catch {
            # Continue on error
        }
    }
    
    # Remove duplicates and fetch all groups at once
    $uniqueGroupIds = $uniqueGroupIds | Sort-Object -Unique
    foreach ($groupId in $uniqueGroupIds) {
        try {
            $groupUri = "https://graph.microsoft.com/v1.0/groups/$groupId"
            $group = Invoke-MgGraphRequest -Uri $groupUri -Method GET
            $groupCache[$groupId] = $group.displayName
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
                    $data | ConvertTo-Html | Out-File (Join-Path $OutputPath "$key.html")
                }
            }
        }

    Write-Host "Export complete: $OutputPath"
}
