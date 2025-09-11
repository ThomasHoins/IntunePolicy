@{
    RootModule = 'ExportIntunePolicies.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'd2f5c3e3-1f4e-4b5e-9c3e-123456789abc'
    Author = 'Thomas Hoins'
    CompanyName = 'Community'
    Copyright = '(c) 2025 Thomas Hoins. All rights reserved.'
    Description = 'Exports Intune policies with group assignments to various formats (CSV, Excel, HTML, Console).'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Export-IntunePolicies')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    RequiredModules = @('Microsoft.Graph.Authentication', 'ImportExcel')
    PrivateData = @{
        PSData = @{
            Tags = @('Intune', 'Export', 'Microsoft.Graph', 'Excel', 'CSV', 'HTML')
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ProjectUri = 'https://github.com/ThomasHoins/IntunePolicy'
            ReleaseNotes = 'Initial version with support for multiple output formats.'
        }
    }
}