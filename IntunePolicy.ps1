# Beschreibung: Dieses Skript exportiert alle Gerätekonfigurationen aus Intune in eine Excel-Datei.
# Module laden

#Install-Module Microsoft.Graph -Scope CurrentUser -Force
#Install-Module ImportExcel -Scope CurrentUser -Force    
#Import-Module Microsoft.Graph
Import-Module ImportExcel



# Funktionen

function windows10CustomConfigurationSettings {
    param (
        $policy
    )
    $settings = @()
    foreach ($setting in $policy.omaSettings) {
        $settings += [PSCustomObject]@{
            PolicyName = $policy.displayName
            version = $policy.version
            description = $policy.description
            lastModifiedDateTime = $policy.lastModifiedDateTime
            createdDateTime = $policy.createdDateTime
            SettingName = $setting.displayName
            SettingDescription = $setting.description
            SettingType = ($setting.'@odata.type').Split('.')[2] 
            OMAUri = $setting.omaUri
            value = $setting.value
        }
    }
    $settings
}
function windows10GeneralConfigurationSettings {
    param (
        $policy
    )

    $settings = @()

    # Metadaten
    $meta = @{
        PolicyName = $policy.displayName
        Version = $policy.version
        Description = $policy.description
        LastModifiedDateTime = $policy.lastModifiedDateTime
        CreatedDateTime = $policy.createdDateTime
    }

    # Properties, die nicht als Setting exportiert werden sollen
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
                PolicyName = $meta.PolicyName
                Version = $meta.Version
                Description = $meta.Description
                LastModifiedDateTime = $meta.LastModifiedDateTime
                CreatedDateTime = $meta.CreatedDateTime
                SettingName = $property.Key
                SettingValue = $value
            }
        }
    }

    return $settings
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
    $odataType = ""
    $policy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$policyID"
    $odataType = ($policy.'@odata.type').Split('.')[2] # Extrahiere den ODataType
    Write-Host "$($policy.displayName); $odataType; $($policy.id)"
    Switch ($odataType) {
        "windows10CustomConfiguration" {
            Write-Host "$($policy.displayName); $odataType; $($policy.id)"
           
            if (-not $groupedPolicies.ContainsKey($odataType)) {
                $groupedPolicies[$odataType] = @()
            }
            $groupedPolicies[$odataType] += windows10CustomConfigurationSettings -policy $policy
            }
        "windows10GeneralConfiguration" {
            Write-Host "$($policy.displayName); $odataType; $($policy.id)"  
            if (-not $groupedPolicies.ContainsKey($odataType)) {
                $groupedPolicies[$odataType] = @()
            }
            $groupedPolicies[$odataType] += windows10GeneralConfigurationSettings -policy $policy
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


