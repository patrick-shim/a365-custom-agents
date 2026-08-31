[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot),

    [ValidateSet('Text', 'Json')]
    [string] $OutputFormat = 'Text',

    [switch] $Strict
)

$modulePath = Join-Path $PSScriptRoot 'modules\KoreaExpert.Validation\KoreaExpert.Validation.psm1'
Import-Module $modulePath -Force

$results = @(Invoke-StaValidationSafely -Check 'Prerequisite validation' -Operation {
    Test-StaPrerequisites -RepositoryRoot $RepositoryRoot
})
Write-StaValidationResults -Results $results -OutputFormat $OutputFormat
exit (Get-StaValidationExitCode -Results $results -Strict:$Strict)
