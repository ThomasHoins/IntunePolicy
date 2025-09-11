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

        [string]$OutputPath = "$env:USERPROFILE\Desktop\Intune-Policies"
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
                $groupUri = "https://graph.microsoft.com/v1.0/groups/$targetGroupId"
                try {
                    $group = Invoke-MgGraphRequest -Uri $groupUri -Method GET
                    $groupNames += $group.displayName
                } catch {
                    $groupNames += "Unknown Group ($targetGroupId)"
                }
            }
        }
        return ($groupNames -join ", ")
    }

    # Function to retrieve Custom Configuration Settings
    function Get-CustomConfigurationSettings {
        param ($policy)
        $settings = @()
        Write-Host "Processing Custom policy: $($policy.displayName)"
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
        Write-Host "Processing Generic policy: $($policy.displayName)"
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
                    AssignedGroups = Get-AssignedGroups -PolicyId $policy.id
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
        $response = Invoke-MgGraphRequest -Method GET -Uri $settingsUri
        Write-Host "Processing Settings Catalog policy: $($policy.name)"
        foreach ($setting in $response.value) {
            $Children= ""
            if ($setting.settingInstance.choiceSettingValue.children.choiceSettingValue) {
                $Children=($setting.settingInstance.choiceSettingValue.children | ForEach-Object {
                    if ($_.choiceSettingValue.value) {
                        "$($_.settingDefinitionId): $($_.choiceSettingValue.value.Split("_")[-1])"
                    } else {
                        "$($_.settingDefinitionId): Not Set"
                    }
                    }
                )
                $Children = $Children -join "; "
            }
            elseif ($setting.settingInstance.choiceSettingValue.children.simpleSettingValue) {
                $Children="$($setting.settingInstance.choiceSettingValue.children.simpleSettingValue.valueState): $($setting.settingInstance.choiceSettingValue.children.simpleSettingValue.value.Split)"
            }
            $Value = $setting.settingInstance.choiceSettingValue.value
            if (![string]::IsNullOrEmpty($Value)) {
                $Value = $Value.Split("_")[-1]
            } else {
                $Value = "Not Set"
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
    If (-not (Get-MgContext)) {
        Write-Host "Connecting to Microsoft Graph..."
        Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All"
    }   

    # Retrieve Device Configuration Policies
    $policies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"
    $groupedPolicies = @{}

    foreach ($policyID in $policies.value.id) {
        $policy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$policyID"
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
    $catalogPolicies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
    if (-not $groupedPolicies.ContainsKey("SettingsCatalog")) {
        $groupedPolicies["SettingsCatalog"] = @()
    }
    foreach ($catalogPolicy in $catalogPolicies.value) {
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
