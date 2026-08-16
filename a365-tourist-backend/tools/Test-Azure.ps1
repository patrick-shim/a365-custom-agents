[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot),

    [switch] $Online,

    [string] $SubscriptionId = '',

    [string[]] $ResourceId = @(),

    [ValidateSet('Text', 'Json')]
    [string] $OutputFormat = 'Text',

    [switch] $Strict
)

$modulePath = Join-Path $PSScriptRoot 'modules\SeoulTourist.Validation\SeoulTourist.Validation.psm1'
Import-Module $modulePath -Force

$results = @(Invoke-StaValidationSafely -Check 'Azure validation' -Operation {
    Test-StaAzureReadiness `
        -RepositoryRoot $RepositoryRoot `
        -Online:$Online `
        -SubscriptionId $SubscriptionId `
        -ResourceId $ResourceId
})
Write-StaValidationResults -Results $results -OutputFormat $OutputFormat
exit (Get-StaValidationExitCode -Results $results -Strict:$Strict)
