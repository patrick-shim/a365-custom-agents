[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot),

    [ValidateSet('Text', 'Json')]
    [string] $OutputFormat = 'Text',

    [switch] $Strict
)

$modulePath = Join-Path $PSScriptRoot 'modules\JapanExpert.Validation\JapanExpert.Validation.psm1'
Import-Module $modulePath -Force

$results = @(Invoke-JexValidationSafely -Check 'Repository validation' -Operation {
    Test-JexRepositoryConfiguration -RepositoryRoot $RepositoryRoot
})
Write-JexValidationResults -Results $results -OutputFormat $OutputFormat
exit (Get-JexValidationExitCode -Results $results -Strict:$Strict)
