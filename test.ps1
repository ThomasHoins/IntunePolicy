# Module laden
Import-Module ImportExcel

# Funktionen

function Extract-FromCustomConfiguration {
    param ($policy)
    $settings = @()
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
        }
    }
    return $settings
}

function Extract-FromGenericConfiguration {
    param ($policy)
    $settings = @()
    $excludedProps = @(
        "displayName", "version", "description", "lastModifiedDateTime", "createdDateTime",
        "id", "@odata.context", "@odata.type", "@microsoft.graph.tips", "roleScopeTagIds",
        "supportsScopeTags", "deviceManagementApplicabilityRuleOsEdition",
        "deviceManagementApplicabilityRuleOsVersion", "deviceManagementApplicabilityRuleDeviceMode"
    )

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
            }
        }
    }

    return $settings
}

# Verbindung zu Microsoft Graph
Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All"

# Gerätekonfigurationen abrufen
$policies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"

# Gruppierung nach Typ
$groupedPolicies = @{}

foreach ($policyID in $policies.value.id) {
    $policy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$policyID"
    $odataType = ($policy.'@odata.type').Split('.')[-1]

    Write-Host "Verarbeite: $($policy.displayName) [$odataType]"

    if (-not $groupedPolicies.ContainsKey($odataType)) {
        $groupedPolicies[$odataType] = @()
    }

    switch ($odataType) {
        "windows10CustomConfiguration" {
            $groupedPolicies[$odataType] += Extract-FromCustomConfiguration -policy $policy
        }
        default {
            $groupedPolicies[$odataType] += Extract-FromGenericConfiguration -policy $policy
        }
    }
}

# Export nach Excel
$excelPath = "$env:USERPROFILE\Desktop\Intune-Policies.xlsx"
foreach ($key in $groupedPolicies.Keys) {
    $sheetName = ($key -replace '[^a-zA-Z0-9]', '_') -replace '^_', ''
    $groupedPolicies[$key] | Export-Excel -Path $excelPath -WorksheetName $sheetName -AutoSize -Append
}

Write-Host "Export abgeschlossen: $excelPath"
