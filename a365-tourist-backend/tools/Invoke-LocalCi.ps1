[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot),

    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Release',

    [ValidateRange(1, 120)]
    [int] $HealthTimeoutSeconds = 20,

    [switch] $SkipToolsSelfTest,

    [switch] $SkipBuild,

    [switch] $SkipTests,

    [switch] $SkipHealth,

    [ValidateSet('Text', 'Json')]
    [string] $OutputFormat = 'Text',

    [switch] $Strict
)

$modulePath = Join-Path $PSScriptRoot 'modules\SeoulTourist.Validation\SeoulTourist.Validation.psm1'
Import-Module $modulePath -Force

$results = @(Invoke-StaValidationSafely -Check 'Local CI' -Operation {
    Invoke-StaLocalCi `
        -RepositoryRoot $RepositoryRoot `
        -Configuration $Configuration `
        -HealthTimeoutSeconds $HealthTimeoutSeconds `
        -SkipToolsSelfTest:$SkipToolsSelfTest `
        -SkipBuild:$SkipBuild `
        -SkipTests:$SkipTests `
        -SkipHealth:$SkipHealth
})
Write-StaValidationResults -Results $results -OutputFormat $OutputFormat
exit (Get-StaValidationExitCode -Results $results -Strict:$Strict)
