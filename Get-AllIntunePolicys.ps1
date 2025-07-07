
<#
.SYNOPSIS
    Exportiert alle Intune-Richtlinien (Konfigurationsprofile, Compliance-Richtlinien, Applikationsrichtlinien etc.) aus Microsoft Endpoint Manager (Intune) in JSON-Dateien und Excel.

.BESCHREIBUNG
    Dieses Skript verbindet sich mit dem Microsoft Graph API über das Microsoft.Graph PowerShell-Modul und exportiert alle relevanten Intune-Richtlinien in strukturierter Form.
    Zusätzlich werden die zugewiesenen Azure AD-Gruppen zu jeder Richtlinie ermittelt und in die Excel-Datei aufgenommen.

.AUTOR
    Thomas Hoins (erweitert durch Copilot)

.VORAUSSETZUNGEN
    - Microsoft.Graph PowerShell-Modul
    - ImportExcel PowerShell-Modul
    - Berechtigungen zum Zugriff auf Microsoft Intune über Microsoft Graph
.VERSION
    1.1
#>

# ============================
# Modulinstallation & Import
# ============================

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}
#Import-Module Microsoft.Graph

if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Install-Module ImportExcel -Scope CurrentUser -Force
}
Import-Module ImportExcel

# ============================
# Funktionen
# ============================

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

function Get-AssignedGroups {
    param (
        [string]$PolicyId
    )

    $assignmentsUri = "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$PolicyId/assignments"
    $assignments = Invoke-MgGraphRequest -Uri $assignmentsUri -Method GET

    $groupNames = @()

    foreach ($assignment in $assignments.value) {
        $targetGroupId = $assignment.target.groupId
        if ($targetGroupId) {
            $groupUri = "https://graph.microsoft.com/v1.0/groups/$targetGroupId"
            try {
                $group = Invoke-MgGraphRequest -Uri $groupUri -Method GET
                $groupNames += $group.displayName
            } catch {
                $groupNames += "Unbekannte Gruppe ($targetGroupId)"
            }
        }
    }

    return ($groupNames -join ", ")
}

# ============================
# Verbindung & Datenabruf
# ============================

Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All", "Group.Read.All"

$policies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"

$groupedPolicies = @{}

foreach ($policyID in $policies.value.id) {
    $policy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations/$policyID"
    $odataType = ($policy.'@odata.type').Split('.')[-1]

    Write-Host "Verarbeite: $($policy.displayName) [$odataType]"

    $assignedGroups = Get-AssignedGroups -PolicyId $policy.id

    if (-not $groupedPolicies.ContainsKey($odataType)) {
        $groupedPolicies[$odataType] = @()
    }

    switch ($odataType) {
        "windows10CustomConfiguration" {
            $settings = Get-CustomConfigurationSettings -policy $policy
        }
        default {
            $settings = Get-GenericConfigurationSettings -policy $policy
        }
    }

    foreach ($setting in $settings) {
        $setting | Add-Member -MemberType NoteProperty -Name "AssignedGroups" -Value $assignedGroups
        $groupedPolicies[$odataType] += $setting
    }
}

# ============================
# Export nach Excel
# ============================

$excelPath = "$env:USERPROFILE\Desktop\Intune-Policies.xlsx"
foreach ($key in $groupedPolicies.Keys) {
    $sheetName = $key
    $groupedPolicies[$key] | Export-Excel -Path $excelPath -WorksheetName $sheetName -AutoSize -Append
}

Write-Host "Export abgeschlossen: $excelPath"
