# IntunePolicy.ps1
## 📝 Beschreibung

Dieses PowerShell-Skript exportiert alle relevanten Intune-Richtlinien aus Microsoft Endpoint Manager (Intune) über die Microsoft Graph API. Es eignet sich ideal zur Dokumentation, Archivierung oder zum Vergleich von Richtlinienständen.

## 📦 Exportierte Inhalte

- Gerätekonfigurationsprofile
- Gerätekonformitätsrichtlinien
- Applikationsschutzrichtlinien
- Applikationskonfigurationsrichtlinien
- Gruppenrichtlinien
- u.v.m.

## ⚙️ Voraussetzungen

- PowerShell 7 oder höher
- Installiertes PowerShell-Modul: `Microsoft.Graph`
- Ein Benutzerkonto mit ausreichenden Rechten zum Lesen von Intune-Richtlinien

## 🚀 Installation

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
