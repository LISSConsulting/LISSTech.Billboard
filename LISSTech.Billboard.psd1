@{
    RootModule        = 'LISSTech.Billboard.psm1'
    ModuleVersion     = '26.267.0'
    GUID              = 'f3a7c2e1-8b4d-4f6a-9c5e-1d2b3a4f5e6c'
    Author            = 'LISS Consulting, Corp.'
    CompanyName       = 'LISS Consulting, Corp.'
    Copyright         = '(c) 2026 LISS Consulting, Corp. All rights reserved.'
    Description       = 'Rich WPF notifications for Windows endpoints — toast and modal layouts, Arabic and RTL text, safe rich links and remote artwork, optional user input, and light, dark, and painting-inspired themes. Builder cmdlets compose notifications from buttons, branding, input, and deferral options. Show-Billboard fires and forgets; Request-Billboard blocks and returns the user''s choice. Works in user sessions via direct DLL calls or from SYSTEM context via ServiceUI. Designed for RMM, MDM, and endpoint management scripts.'

    PowerShellVersion      = '5.1'
    CompatiblePSEditions   = @('Desktop')
    ProcessorArchitecture  = 'Amd64'

    RequiredAssemblies = @('Assembly\LISSTech.Billboard.dll')

    FunctionsToExport = @(
        'New-BillboardButton'
        'New-BillboardBranding'
        'New-BillboardInput'
        'New-BillboardNotification'
        'Show-Billboard'
        'Request-Billboard'
        'Register-BillboardDeferral'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    FileList = @(
        'LISSTech.Billboard.psd1'
        'LISSTech.Billboard.psm1'
        'Assembly\LISSTech.Billboard.dll'
        'Bin\Billboard.exe'
        'Bin\ServiceUI.exe'
    )

    PrivateData = @{
        PSData = @{
            Tags         = @('Windows', 'WPF', 'Notification', 'Toast', 'Modal', 'Endpoint', 'RMM', 'MDM', 'MSP', 'ServiceUI', 'Branding', 'DarkMode')
            LicenseUri   = 'https://github.com/LISSConsulting/LISSTech.Billboard/blob/trunk/LICENSE'
            ProjectUri   = 'https://github.com/LISSConsulting/LISSTech.Billboard'
            ReleaseNotes = 'Adds Arabic and RTL layout, safe PNG/JPG/GIF remote artwork, Starry Night, Water Lilies, and Great Wave palettes with animated gradients, modal text input, safe HTTPS autolinks and image-alt rendering, and lossless SYSTEM-to-user notification text transport through ServiceUI.'
        }
    }
}
