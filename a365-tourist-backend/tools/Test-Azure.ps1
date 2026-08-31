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

$modulePath = Join-Path $PSScriptRoot 'modules\JapanExpert.Validation\JapanExpert.Validation.psm1'
Import-Module $modulePath -Force

$results = @(Invoke-JexValidationSafely -Check 'Azure validation' -Operation {
    Test-JexAzureReadiness `
        -RepositoryRoot $RepositoryRoot `
        -Online:$Online `
        -SubscriptionId $SubscriptionId `
        -ResourceId $ResourceId
})
Write-JexValidationResults -Results $results -OutputFormat $OutputFormat
exit (Get-JexValidationExitCode -Results $results -Strict:$Strict)
