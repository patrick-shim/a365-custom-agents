[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot),

    [ValidateSet('Text', 'Json')]
    [string] $OutputFormat = 'Text',

    [switch] $Strict
)

$modulePath = Join-Path $PSScriptRoot 'modules\SeoulTourist.Validation\SeoulTourist.Validation.psm1'
Import-Module $modulePath -Force

$results = @(Invoke-StaValidationSafely -Check 'Repository validation' -Operation {
    Test-StaRepositoryConfiguration -RepositoryRoot $RepositoryRoot
})
Write-StaValidationResults -Results $results -OutputFormat $OutputFormat
exit (Get-StaValidationExitCode -Results $results -Strict:$Strict)
