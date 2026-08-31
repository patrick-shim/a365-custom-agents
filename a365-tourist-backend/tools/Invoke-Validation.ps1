[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot),

    [switch] $OnlineAzure,

    [string] $SubscriptionId = '',

    [string[]] $ResourceId = @(),

    [switch] $RequirePurviewImplemented,

    [switch] $CheckPurviewTenantPolicy,

    [ValidateSet('Text', 'Json')]
    [string] $OutputFormat = 'Text',

    [switch] $Strict
)

$modulePath = Join-Path $PSScriptRoot 'modules\KoreaExpert.Validation\KoreaExpert.Validation.psm1'
Import-Module $modulePath -Force

$allResults = @(Invoke-StaValidationSafely -Check 'Aggregate validation' -Operation {
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($result in @(Test-StaPrerequisites `
        -RepositoryRoot $RepositoryRoot `
        -SkipCloudCliVersionCommands:(-not $OnlineAzure))) {
        $results.Add($result)
    }
    foreach ($result in @(Test-StaRepositoryConfiguration -RepositoryRoot $RepositoryRoot)) {
        $results.Add($result)
    }
    foreach ($result in @(Test-StaAzureReadiness `
        -RepositoryRoot $RepositoryRoot `
        -Online:$OnlineAzure `
        -SubscriptionId $SubscriptionId `
        -ResourceId $ResourceId)) {
        $results.Add($result)
    }
    foreach ($result in @(Test-StaPurviewReadiness `
        -RepositoryRoot $RepositoryRoot `
        -RequireImplemented:$RequirePurviewImplemented `
        -Online:$CheckPurviewTenantPolicy `
        -CheckTenantPolicy:$CheckPurviewTenantPolicy)) {
        $results.Add($result)
    }
    @($results)
})
Write-StaValidationResults -Results $allResults -OutputFormat $OutputFormat
exit (Get-StaValidationExitCode -Results $allResults -Strict:$Strict)
