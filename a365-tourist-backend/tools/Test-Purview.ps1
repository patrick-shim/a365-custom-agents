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

    [string] $ProbeText = 'Japan Expert synthetic Purview validation probe.',

    [switch] $ExpectBlock,

    [ValidateRange(1, 120)]
    [int] $ProbeTimeoutSeconds = 30,

    [ValidateSet('Text', 'Json')]
    [string] $OutputFormat = 'Text',

    [switch] $Strict
)

$modulePath = Join-Path $PSScriptRoot 'modules\JapanExpert.Validation\JapanExpert.Validation.psm1'
Import-Module $modulePath -Force

$results = @(Invoke-JexValidationSafely -Check 'Purview validation' -Operation {
    Test-JexPurviewReadiness `
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
Write-JexValidationResults -Results $results -OutputFormat $OutputFormat
exit (Get-JexValidationExitCode -Results $results -Strict:$Strict)
