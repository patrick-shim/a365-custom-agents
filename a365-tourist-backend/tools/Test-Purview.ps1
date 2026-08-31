[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot),

    [switch] $RequireImplemented,

    [switch] $Online,

    [switch] $CheckTenantPolicy,

    [switch] $ProbePolicy,

    [string] $UserId = '',

    [string] $ApplicationId = '',

    [string] $BlueprintId = '',

    [string] $AgentInstanceId = '',

    [string] $AccessTokenEnvironmentVariable = 'PURVIEW_GRAPH_ACCESS_TOKEN',

    [string] $ProbeText = 'Korea Expert Assistant synthetic Purview validation probe.',

    [switch] $ExpectBlock,

    [ValidateRange(1, 120)]
    [int] $ProbeTimeoutSeconds = 30,

    [ValidateSet('Text', 'Json')]
    [string] $OutputFormat = 'Text',

    [switch] $Strict
)

$modulePath = Join-Path $PSScriptRoot 'modules\KoreaExpert.Validation\KoreaExpert.Validation.psm1'
Import-Module $modulePath -Force

$results = @(Invoke-StaValidationSafely -Check 'Purview validation' -Operation {
    Test-StaPurviewReadiness `
        -RepositoryRoot $RepositoryRoot `
        -RequireImplemented:$RequireImplemented `
        -Online:$Online `
        -CheckTenantPolicy:$CheckTenantPolicy `
        -ProbePolicy:$ProbePolicy `
        -UserId $UserId `
        -ApplicationId $ApplicationId `
        -BlueprintId $BlueprintId `
        -AgentInstanceId $AgentInstanceId `
        -AccessTokenEnvironmentVariable $AccessTokenEnvironmentVariable `
        -ProbeText $ProbeText `
        -ExpectBlock:$ExpectBlock `
        -ProbeTimeoutSeconds $ProbeTimeoutSeconds
})
Write-StaValidationResults -Results $results -OutputFormat $OutputFormat
exit (Get-StaValidationExitCode -Results $results -Strict:$Strict)
