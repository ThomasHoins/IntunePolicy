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
                "$($_.settingDefinitionId): $($_.choiceSettingValue.value.Split("_")[-1])"
                } -join "; "
                )
        }
        elseif ($setting.settingInstance.choiceSettingValue.children.simpleSettingValue) {
            $Children="$($setting.settingInstance.choiceSettingValue.children.simpleSettingValue.valueState): $($setting.settingInstance.choiceSettingValue.children.simpleSettingValue.value.Split)"
        }

        $settings += [PSCustomObject]@{
            PolicyName          = $policy.name
            Description         = $policy.description
            LastModifiedDateTime= $policy.lastModifiedDateTime
            CreatedDateTime     = $policy.createdDateTime
            SettingName         = $setting.settingInstance.settingDefinitionId
            Value               = $setting.settingInstance.choiceSettingValue.value.Split("_")[-1]
            Children            = $Children
        }
    }
    return $settings
}
$groupedPolicies = @{}
$catalogPolicies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
if (-not $groupedPolicies.ContainsKey("SettingsCatalog")) {
    $groupedPolicies["SettingsCatalog"] = @()
}
foreach ($catalogPolicy in $catalogPolicies.value) {
    $Policysettings = Get-SettingsCatalogSettings -policy $catalogPolicy
    $groupedPolicies["SettingsCatalog"] += $Policysettings
}
#$Policysettings["SettingsCatalog"]  | Format-Table -AutoSize