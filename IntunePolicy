# Module installieren (falls noch nicht vorhanden)
Install-Module Microsoft.Graph -Scope CurrentUser -Force
Install-Module ImportExcel -Scope CurrentUser -Force

# Mit Graph verbinden
Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All"

# Alle Gerätekonfigurationen holen
$policies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"

$excelData = @()

# Für jede Richtlinie die Einstellungen abrufen
foreach ($policy in $policies.value) {
    $settingsUri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$($policy.id)/settings"
    $settings = Invoke-MgGraphRequest -Method GET -Uri $settingsUri

    foreach ($setting in $settings.value) {
        $excelData += [PSCustomObject]@{
            PolicyName  = $policy.displayName
            PolicyId    = $policy.id
            SettingId   = $setting.id
            Definition  = $setting.definitionId
            Value       = $setting.valueJson
        }
    }
}

# Export in Excel-Datei
$excelData | Export-Excel -Path ".\IntuneDevicePolicies.xlsx" -AutoSize -WorksheetName "Policies"
