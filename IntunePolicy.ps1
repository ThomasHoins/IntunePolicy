# Beschreibung: Dieses Skript exportiert alle Gerätekonfigurationen aus Intune in eine Excel-Datei.
# Module laden

#Install-Module Microsoft.Graph -Scope CurrentUser -Force
#Install-Module ImportExcel -Scope CurrentUser -Force    
#Import-Module Microsoft.Graph
#Import-Module ImportExcel



# Funktionen definieren


function windows10CustomConfigurationSettings {
    param (
        $policy
    )
        # Einstellungen extrahieren 
    $settings = @()
        foreach ($setting in $policy) {
            $settings += [PSCustomObject]@{
                PolicyName = $policy.displayName
                version = $policy.version
                description = $policy.description
                lastModifiedDateTime = $policy.lastModifiedDateTime
                createdDateTime = $policy.createdDateTime
                SettingName = $setting.omaSettings.displayName
                SettingDescription = $setting.omaSettings.description
                SettingType = ($setting.omaSettings.'@odata.type').Split('.')[2] # Extrahiere den ODataType
                OMAUri = $setting.omaSettings.omaUri
                value = $setting.omaSettings.value
           }
        }
    $settings
        
}

#Main-Skript

# Mit Graph verbinden
Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All"

# Alle Gerätekonfigurationen abrufen
$policies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"

# Dictionary zur Gruppierung nach @odata.type
$groupedPolicies = @{}


# Richtlinien durchgehen
foreach ($policyID in $policies.value.id) {
    $policy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$policyID"

    $odataType = ($policy.'@odata.type').Split('.')[2] # Extrahiere den ODataType
    Write-Host "$($policy.displayName) $odataType"
    Switch ($odataType) {
        "windows10CustomConfiguration" {
            $groupedPolicies[$odataType] += windows10CustomConfigurationSettings -policy $policy  
        }
    }   
}

# Export nach Excel mit Tabs pro ODataType
$excelPath = "$env:USERPROFILE\Desktop\Intune-Policies.xlsx"
foreach ($key in $groupedPolicies.Keys) {
    $sheetName = ($key -replace '[^a-zA-Z0-9]', '_') -replace '^_', ''
    $groupedPolicies[$key] | Export-Excel -Path $excelPath -WorksheetName $sheetName -AutoSize -Append
}

Write-Host "Export abgeschlossen: $excelPath"


