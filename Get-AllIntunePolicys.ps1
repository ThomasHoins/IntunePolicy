<#
.SYNOPSIS
    Exportiert alle Intune-Richtlinien (Konfigurationsprofile, Compliance-Richtlinien, Applikationsrichtlinien etc.) aus Microsoft Endpoint Manager (Intune) in JSON-Dateien.

.BESCHREIBUNG
    Dieses Skript verbindet sich mit dem Microsoft Graph API über das Microsoft.Graph PowerShell-Modul und exportiert alle relevanten Intune-Richtlinien in strukturierter Form.
    Die exportierten Daten werden in einem lokalen Verzeichnis gespeichert und können zur Dokumentation oder für Backup-Zwecke verwendet werden.

.AUTOR
    Thomas Hoins

.VORAUSSETZUNGEN
    - Microsoft.Graph PowerShell-Modul
    - Berechtigungen zum Zugriff auf Microsoft Intune über Microsoft Graph
.VERSION
    1.0

#>

# ============================
# Modulinstallation & Import
# ============================

# Microsoft.Graph installieren (wenn nicht vorhanden)
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}
Import-Module Microsoft.Graph

# ImportExcel installieren (wenn nicht vorhanden)
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Install-Module ImportExcel -Scope CurrentUser -Force
}
Import-Module ImportExcel


# Funktionen

function Get-CustomConfigurationSettings {
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

function Get-GenericConfigurationSettings {
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
            $groupedPolicies[$odataType] += Get-CustomConfigurationSettings -policy $policy
        }
        default {
            $groupedPolicies[$odataType] += Get-GenericConfigurationSettings -policy $policy
        }
    }
}

# Export nach Excel
$excelPath = "$env:USERPROFILE\Desktop\Intune-Policies.xlsx"
foreach ($key in $groupedPolicies.Keys) {
    $sheetName = $key  # Optional: Sheet-Namen bereinigen, falls nötig
    $groupedPolicies[$key] | Export-Excel -Path $excelPath -WorksheetName $sheetName -AutoSize -Append
}

Write-Host "Export abgeschlossen: $excelPath"
