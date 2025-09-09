@{
    RootModule = 'ExportIntunePolicies.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'd2f5c3e3-1f4e-4b5e-9c3e-123456789abc'
    Author = 'Thomas Hoins'
    CompanyName = 'Community'
    Copyright = '(c) 2025 Thomas Hoins. All rights reserved.'
    Description = 'Exportiert Intune-Richtlinien mit Gruppeninformationen in verschiedene Formate.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Export-IntunePolicies')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    RequiredModules = @('Microsoft.Graph', 'ImportExcel')
    PrivateData = @{
        PSData = @{
            Tags = @('Intune', 'Export', 'Microsoft.Graph', 'Excel', 'CSV', 'HTML')
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ProjectUri = 'https://github.com/ThomasHoins/IntunePolicy'
            ReleaseNotes = 'Initiale Version mit Unterstützung für mehrere Ausgabeformate.'
        }
    }
}
