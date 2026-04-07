@{
    RootModule        = 'LISSTech.Billboard.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'f3a7c2e1-8b4d-4f6a-9c5e-1d2b3a4f5e6c'
    Author            = 'Marcin Wisniowski <mwisniowski@lisstech.com>'
    CompanyName       = 'LISS Consulting, Corp.'
    Copyright         = '(c) LISS Consulting. All rights reserved.'
    Description       = 'LISSTech Billboard notification system for Windows endpoints.'
    PowerShellVersion = '5.1'
    RequiredAssemblies = @('Assembly\LISSTech.Billboard.dll')
    FunctionsToExport = @(
        'New-BillboardButton',
        'New-BillboardBranding',
        'New-BillboardNotification',
        'Show-Billboard',
        'Request-Billboard',
        'Register-BillboardDeferral'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
}
