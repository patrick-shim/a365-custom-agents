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

$modulePath = Join-Path $PSScriptRoot 'modules\JapanExpert.Validation\JapanExpert.Validation.psm1'
Import-Module $modulePath -Force

$allResults = @(Invoke-JexValidationSafely -Check 'Aggregate validation' -Operation {
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($result in @(Test-JexPrerequisites `
        -RepositoryRoot $RepositoryRoot `
        -SkipCloudCliVersionCommands:(-not $OnlineAzure))) {
        $results.Add($result)
    }
    foreach ($result in @(Test-JexRepositoryConfiguration -RepositoryRoot $RepositoryRoot)) {
        $results.Add($result)
    }
    foreach ($result in @(Test-JexAzureReadiness `
        -RepositoryRoot $RepositoryRoot `
        -Online:$OnlineAzure `
        -SubscriptionId $SubscriptionId `
        -ResourceId $ResourceId)) {
        $results.Add($result)
    }
    foreach ($result in @(Test-JexDeploymentBoundary -RepositoryRoot $RepositoryRoot)) {
        $results.Add($result)
    }
    foreach ($result in @(Test-JexPurviewReadiness `
        -RepositoryRoot $RepositoryRoot `
        -RequireImplemented:$RequirePurviewImplemented `
        -Online:$CheckPurviewTenantPolicy `
        -CheckTenantPolicy:$CheckPurviewTenantPolicy)) {
        $results.Add($result)
    }
    @($results)
})
Write-JexValidationResults -Results $allResults -OutputFormat $OutputFormat
exit (Get-JexValidationExitCode -Results $allResults -Strict:$Strict)
