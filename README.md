# Intune Policy Exporter

This PowerShell module allows you to export Microsoft Intune device configuration and Settings Catalog policies to various formats (CSV, Excel, HTML, or directly to the console). It retrieves policy details, assignments, and settings using Microsoft Graph.

## Features

- Export Intune device configuration and Settings Catalog policies
- Output formats: CSV, Excel, HTML, or Console
- Includes policy assignments and detailed settings
- Automatically installs required PowerShell modules if missing

## Requirements

- PowerShell 5.1 or later
- [Microsoft.Graph.Authentication](https://www.powershellgallery.com/packages/Microsoft.Graph.Authentication)
- [ImportExcel](https://www.powershellgallery.com/packages/ImportExcel) (only for Excel export)

## Installation

Clone this repository or download the `ExportIntunePolicies.psm1` file.

```powershell
Import-Module .\ExportIntunePolicies.psm1
```

## Usage

```powershell
Export-IntunePolicies -OutputFormat CSV
Export-IntunePolicies -OutputFormat Excel -OutputPath "C:\Exports\Intune"
Export-IntunePolicies -OutputFormat HTML
Export-IntunePolicies -OutputFormat Console
```

- `-OutputFormat`: Choose between `CSV`, `Excel`, `HTML`, or `Console`. Default is `CSV`.
- `-OutputPath`: (Optional) Specify the export directory. Default is `Desktop\Intune-Policies`.

## Example

Export all policies to Excel in a custom directory:

```powershell
Export-IntunePolicies -OutputFormat Excel -OutputPath "C:\Exports\Intune"
```

## Notes

- The script will prompt for authentication to Microsoft Graph if not already connected.
- The module will attempt to install required dependencies automatically if they are not present.

## Author

Thomas Hoins

## License

MIT