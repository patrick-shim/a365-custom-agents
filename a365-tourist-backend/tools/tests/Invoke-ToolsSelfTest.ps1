[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()
$assertionCount = 0

function Assert-ToolsCondition {
    param(
        [Parameter(Mandatory)]
        [bool] $Condition,

        [Parameter(Mandatory)]
        [string] $Message
    )

    $script:assertionCount++
    if ($Condition) {
        Write-Output "PASS $Message"
    }
    else {
        Write-Output "FAIL $Message"
        $script:failures.Add($Message)
    }
}

$toolFiles = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'tools') -Recurse -File |
    Where-Object {
        $_.FullName -notmatch '[\\/]node_modules[\\/]' -and
        $_.Extension -in @('.ps1', '.psm1')
    })
foreach ($file in $toolFiles) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors) | Out-Null
    Assert-ToolsCondition -Condition ($parseErrors.Count -eq 0) `
        -Message "PowerShell syntax: $([System.IO.Path]::GetRelativePath($RepositoryRoot, $file.FullName))"
}

$modulePath = Join-Path $RepositoryRoot 'tools\modules\KoreaExpert.Validation\KoreaExpert.Validation.psm1'
Import-Module $modulePath -Force
$validationModuleContent = Get-Content -LiteralPath $modulePath -Raw
Assert-ToolsCondition -Condition (
    $validationModuleContent -match '(?s)Get-FeatureConfiguration\s+`\s*-FeatureScenario\s+KnowYourData\s+`\s*-ErrorAction\s+Stop' -and
    $validationModuleContent -match '\$matchingPolicies\.Count\s+-gt\s+0') `
    -Message 'Purview tenant policy read evaluates enabled KnowYourData policies by required behavior'
Assert-ToolsCondition -Condition (
    $validationModuleContent -match '(?s)\$purviewTestRemediation\s*=.*?\$purviewTests\.Output') `
    -Message 'Purview test-process failures surface their captured diagnostic output'

$aggregateValidationContent = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'tools\Invoke-Validation.ps1') -Raw
Assert-ToolsCondition -Condition (
    $aggregateValidationContent.Contains(
        '-SkipCloudCliVersionCommands:(-not $OnlineAzure)',
        [StringComparison]::Ordinal)) `
    -Message 'Offline aggregate validation skips Azure CLI version commands by default'

$milestone = Get-StaMilestoneState -RepositoryRoot $RepositoryRoot
Assert-ToolsCondition -Condition ($milestone.Current.status -eq 'active') `
    -Message 'The selected current milestone is active'
Assert-ToolsCondition -Condition (@($milestone.Manifest.milestones | Where-Object status -eq 'active').Count -eq 1) `
    -Message 'Exactly one milestone is active'
if ($milestone.Current.id -eq 'M0') {
    Assert-ToolsCondition -Condition (-not $milestone.Current.allowsTenantMutations) `
        -Message 'M0 prohibits tenant mutations'
}
$milestoneJson = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'docs\milestones\milestones.json') -Raw
$milestoneSchemaPath = Join-Path $RepositoryRoot 'docs\milestones\milestones.schema.json'
Assert-ToolsCondition -Condition (Test-Json -Json $milestoneJson -SchemaFile $milestoneSchemaPath -ErrorAction Stop) `
    -Message 'Milestone manifest conforms to its declared JSON schema'

$frontendContractPath = Join-Path $RepositoryRoot 'contracts\frontend-backend-contract.json'
$frontendContractSchemaPath = Join-Path $RepositoryRoot 'contracts\frontend-backend-contract.schema.json'
$frontendContractJson = Get-Content -LiteralPath $frontendContractPath -Raw
Assert-ToolsCondition -Condition (
    Test-Json -Json $frontendContractJson -SchemaFile $frontendContractSchemaPath -ErrorAction Stop) `
    -Message 'Frontend backend contract conforms to its declared JSON schema'
$frontendContract = $frontendContractJson | ConvertFrom-Json -Depth 20
Assert-ToolsCondition -Condition (
    $frontendContract.contractId -eq 'korea-expert-shared-backend' -and
    $frontendContract.contractVersion -match '^\d+\.\d+\.\d+$' -and
    @($frontendContract.frontends).Count -eq 2 -and
    @($frontendContract.frontends.route) -contains '/api/messages' -and
    @($frontendContract.frontends.route) -contains '/api/messages/obo') `
    -Message 'Frontend backend contract declares both protected routes'

$repositoryResults = @(Test-StaRepositoryConfiguration -RepositoryRoot $RepositoryRoot)
Assert-ToolsCondition -Condition (@($repositoryResults | Where-Object Status -eq 'Fail').Count -eq 0) `
    -Message 'Repository validation has no failures'
foreach ($repositoryCheck in @('Two protected host routes', 'Frontend channel audience mapping')) {
    Assert-ToolsCondition -Condition (@($repositoryResults | Where-Object {
        $_.Check -eq $repositoryCheck -and $_.Status -eq 'Pass'
    }).Count -eq 1) -Message "$repositoryCheck validation passes"
}

$repositoryBoundaryFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "korea-expert-repository-boundary-fixture-$([guid]::NewGuid())"
try {
    $repositoryBoundaryFixtureFiles = @(
        'KoreaExpertAgent.slnx',
        'Directory.Packages.props',
        'README.md',
        'docs\milestones\milestones.json',
        'contracts\frontend-backend-contract.json',
        'contracts\frontend-backend-contract.schema.json',
        'server\agent\KoreaExpert.Agent\KoreaExpert.Agent.csproj',
        'server\agent-host\KoreaExpert.AgentHost\KoreaExpert.AgentHost.csproj',
        'server\agent-host\KoreaExpert.AgentHost\Program.cs',
        'server\agent-host\KoreaExpert.AgentHost\KoreaExpertApplication.cs',
        'server\agent-host\KoreaExpert.AgentHost\AgentIdentityOboTokenExchange.cs',
        'server\agent-host\KoreaExpert.AgentHost\AgentFrontendIdentityBinding.cs',
        'server\agent-host\KoreaExpert.AgentHost\InternalMcpOptions.cs',
        'server\agent-host\KoreaExpert.AgentHost\InternalMcpToolCatalog.cs',
        'server\agent-host\KoreaExpert.AgentHost\appsettings.json',
        'server\agent-host\KoreaExpert.AgentHost\appsettings.Development.json',
        'infra\main.bicep',
        'infra\modules\agent-host-container-app.bicep',
        'infra\modules\mcp-api-application.bicep',
        'infra\modules\attractions-mcp-container-app.bicep',
        'infra\modules\weather-mcp-container-app.bicep',
        'infra\modules\accommodation-mcp-container-app.bicep',
        'infra\modules\currency-mcp-container-app.bicep',
        'server\mcp\shared\KoreaExpert.Mcp.Hosting\McpWorkloadAuthorization.cs',
        'tests\KoreaExpert.AgentHost.Tests\AgentIdentityAuthorizationOptionsTests.cs',
        'tests\KoreaExpert.AgentHost.Tests\AgentIdentityOboTokenExchangeTests.cs',
        'tests\KoreaExpert.AgentHost.Tests\AgentFrontendIdentityBindingTests.cs',
        'tests\KoreaExpert.AgentHost.Tests\ObservabilityTokenCacheTests.cs',
        'tests\KoreaExpert.AgentHost.Tests\InternalMcpToolCatalogTests.cs',
        'tests\KoreaExpert.Mcp.Hosting.Tests\McpWorkloadAuthorizationTests.cs'
    )
    foreach ($relativePath in $repositoryBoundaryFixtureFiles) {
        $destination = Join-Path $repositoryBoundaryFixtureRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot $relativePath) -Destination $destination
    }
    New-Item -ItemType Directory -Path (Join-Path $repositoryBoundaryFixtureRoot 'tools') -Force | Out-Null

    $boundaryBaselineResults = @(Test-StaRepositoryConfiguration -RepositoryRoot $repositoryBoundaryFixtureRoot)
    Assert-ToolsCondition -Condition (@($boundaryBaselineResults | Where-Object Status -eq 'Fail').Count -eq 0) `
        -Message 'Repository boundary fixture starts from a passing offline baseline'

    $boundaryMutations = @(
        @{
            Name  = 'stale appsettings OBO connection setting'
            Check = 'OBO authorization configuration boundary'
            Path  = 'server\agent-host\KoreaExpert.AgentHost\appsettings.json'
            Old   = '"AzureBotOAuthConnectionName": "korea-expert-obo"'
            New   = ('"AzureBotOAuthConnectionName": "korea-expert-obo",' + [Environment]::NewLine +
                '            "OBOConnectionName": "OboServiceConnection"')
        },
        @{
            Name  = 'stale Bicep OBO scopes setting'
            Check = 'OBO authorization configuration boundary'
            Path  = 'infra\modules\agent-host-container-app.bicep'
            Old   = 'AgentApplication__UserAuthorization__Handlers__obo-user__Settings__AzureBotOAuthConnectionName'
            New   = 'AgentApplication__UserAuthorization__Handlers__obo-user__Settings__OBOScopes__0'
        },
        @{
            Name  = 'parent fmi_path child-token method removal'
            Check = 'Two-stage child Agent Identity OBO'
            Path  = 'server\agent-host\KoreaExpert.AgentHost\AgentIdentityOboTokenExchange.cs'
            Old   = 'GetAgenticApplicationTokenAsync('
            New   = 'GetAgenticApplicationTokenForChildAsync('
        },
        @{
            Name  = 'OBO child Bicep selector removal'
            Check = 'Two-stage child Agent Identity OBO'
            Path  = 'infra\modules\agent-host-container-app.bicep'
            Old   = "name: 'AgentIdentityObo__AgentId'"
            New   = "name: 'AgentIdentityObo__LegacyAgentId'"
        },
        @{
            Name  = 'custom MCP default child exchange removal'
            Check = 'OBO per-resource child exchanges'
            Path  = 'server\agent-host\KoreaExpert.AgentHost\KoreaExpertApplication.cs'
            Old   = '[AgentIdentityAuthorizationScopes.InternalMcpDefault(_internalMcpOptions.Audience)]'
            New   = '[mcpScope]'
        },
        @{
            Name  = 'S2S observability endpoint removal'
            Check = 'App-only child observability'
            Path  = 'server\agent-host\KoreaExpert.AgentHost\Program.cs'
            Old   = 'options.Agent365.UseS2SEndpoint = true;'
            New   = 'options.Agent365.UseS2SEndpoint = false;'
        },
        @{
            Name  = 'authenticated frontend identity resolver removal'
            Check = 'Authenticated frontend identity binding'
            Path  = 'server\agent-host\KoreaExpert.AgentHost\KoreaExpertApplication.cs'
            Old   = '_frontendIdentityBinding.Resolve(turnContext.Activity, frontendMode)'
            New   = '_frontendIdentityBinding.ResolveUnbound(turnContext.Activity, frontendMode)'
        },
        @{
            Name  = 'v2 MCP application ID audience removal'
            Check = 'MCP v2 token audience boundary'
            Path  = 'infra\main.bicep'
            Old   = 'mcpTokenAudience: mcpApiApplication.outputs.applicationId'
            New   = 'mcpTokenAudience: mcpApiApplication.outputs.audience'
        },
        @{
            Name  = 'one stale schema fingerprint'
            Check = 'Canonical MCP schema fingerprints'
            Path  = 'server\agent-host\KoreaExpert.AgentHost\InternalMcpOptions.cs'
            Old   = '"4C1A15FF94EA712679A8D1444499DE6C548D25316423C7A32C896732E95C8A27"'
            New   = '"STALE-SCHEMA-FINGERPRINT"'
        },
        @{
            Name  = 'unexpected-tool rejection test removal'
            Check = 'Canonical MCP schema fingerprints'
            Path  = 'tests\KoreaExpert.AgentHost.Tests\InternalMcpToolCatalogTests.cs'
            Old   = 'RejectsUnexpectedToolBeforeModelExposure'
            New   = 'AllowsUnexpectedToolBeforeModelExposure'
        },
        @{
            Name  = 'nested-schema rejection test removal'
            Check = 'Canonical MCP schema fingerprints'
            Path  = 'tests\KoreaExpert.AgentHost.Tests\InternalMcpToolCatalogTests.cs'
            Old   = 'RejectsAlteredNestedSchemaBeforeModelExposure'
            New   = 'AllowsAlteredNestedSchemaBeforeModelExposure'
        },
        @{
            Name  = 'non-local HTTPS requirement removal'
            Check = 'Production MCP HTTPS endpoint enforcement'
            Path  = 'server\agent-host\KoreaExpert.AgentHost\Program.cs'
            Old   = 'options.HasValidEndpoints(requireHttps: !isLocalEnvironment)'
            New   = 'options.HasValidEndpoints(requireHttps: false)'
        }
    )
    foreach ($mutation in $boundaryMutations) {
        $mutationPath = Join-Path $repositoryBoundaryFixtureRoot $mutation.Path
        $originalContent = Get-Content -LiteralPath $mutationPath -Raw
        $markerPresent = $originalContent.Contains($mutation.Old, [StringComparison]::Ordinal)
        Assert-ToolsCondition -Condition $markerPresent `
            -Message "Repository boundary fixture contains marker for $($mutation.Name)"
        if (-not $markerPresent) {
            continue
        }

        try {
            $originalContent.Replace($mutation.Old, $mutation.New) |
                Set-Content -LiteralPath $mutationPath -NoNewline
            $mutationResults = @(Test-StaRepositoryConfiguration -RepositoryRoot $repositoryBoundaryFixtureRoot)
            Assert-ToolsCondition -Condition (@($mutationResults | Where-Object {
                $_.Check -eq $mutation.Check -and $_.Status -eq 'Fail'
            }).Count -eq 1) -Message "$($mutation.Check) rejects $($mutation.Name)"
        }
        finally {
            Set-Content -LiteralPath $mutationPath -Value $originalContent -NoNewline
        }
    }
}
finally {
    Remove-Item -LiteralPath $repositoryBoundaryFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$azureResults = @(Test-StaAzureReadiness -RepositoryRoot $RepositoryRoot)
Assert-ToolsCondition -Condition (@($azureResults | Where-Object Status -eq 'Fail').Count -eq 0) `
    -Message 'Offline Azure validation has no failures'
Assert-ToolsCondition -Condition (@($azureResults | Where-Object { $_.Check -eq 'Azure account' -and $_.Status -eq 'Skip' }).Count -eq 1) `
    -Message 'Azure tenant calls are opt-in'
$unauthorizedAzureResults = @(Test-StaAzureReadiness `
    -RepositoryRoot $RepositoryRoot `
    -ResourceId '/subscriptions/test/resourceGroups/test/providers/Microsoft.Test/resources/test')
Assert-ToolsCondition -Condition (@($unauthorizedAzureResults | Where-Object { $_.Check -eq 'Online switch' -and $_.Status -eq 'Fail' }).Count -eq 1) `
    -Message 'Azure resource parameters fail without explicit online authorization'

$capabilityFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "korea-expert-capability-fixture-$([guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path (Join-Path $capabilityFixtureRoot 'docs\milestones') -Force | Out-Null
    $capabilityManifest = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'docs\milestones\milestones.json') -Raw |
        ConvertFrom-Json -Depth 20
    $capabilityManifest.milestones |
        Where-Object id -eq $capabilityManifest.currentMilestone |
        ForEach-Object { $_.allowsTenantReads = $false }
    $capabilityManifest | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath (Join-Path $capabilityFixtureRoot 'docs\milestones\milestones.json')
    $capabilityResults = @(Test-StaAzureReadiness -RepositoryRoot $capabilityFixtureRoot -Online)
    Assert-ToolsCondition -Condition (@($capabilityResults | Where-Object { $_.Check -eq 'Milestone tenant-read authorization' -and $_.Status -eq 'Fail' }).Count -eq 1) `
        -Message 'Milestone capability gate blocks online Azure reads'
}
finally {
    Remove-Item -LiteralPath $capabilityFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$purviewResults = @(Test-StaPurviewReadiness -RepositoryRoot $RepositoryRoot)
Assert-ToolsCondition -Condition (@($purviewResults | Where-Object Status -eq 'Fail').Count -eq 0) `
    -Message 'Purview readiness has no failures for the current milestone state'
if ($milestone.Current.id -eq 'M0') {
    Assert-ToolsCondition -Condition (@($purviewResults | Where-Object { $_.Check -eq 'Agent Framework Purview package' -and $_.Status -eq 'Skip' }).Count -eq 1) `
        -Message 'M0 keeps Purview implementation deferred'
}
else {
    Assert-ToolsCondition -Condition (@($purviewResults | Where-Object { $_.Check -eq 'Milestone authorization' -and $_.Status -eq 'Pass' }).Count -eq 1) `
    -Message 'Post-foundation milestones authorize Purview readiness checks'
}

$invalidProbeResults = @(Test-StaPurviewReadiness -RepositoryRoot $RepositoryRoot -ProbePolicy)
Assert-ToolsCondition -Condition (@($invalidProbeResults | Where-Object { $_.Check -eq 'Online switch' -and $_.Status -eq 'Fail' }).Count -eq 1) `
    -Message 'Purview probes require explicit online authorization'

$toolMutationFindings = @($toolFiles | ForEach-Object {
    Find-StaForbiddenToolMutation `
        -Content (Get-Content -LiteralPath $_.FullName -Raw) `
        -Source ([IO.Path]::GetRelativePath($RepositoryRoot, $_.FullName))
})
Assert-ToolsCondition -Condition ($toolMutationFindings.Count -eq 0) `
    -Message 'Validation tools contain no disallowed cloud CLI commands'

$syntheticMutation = 'a365 --version'
Assert-ToolsCondition -Condition (@(Find-StaForbiddenToolMutation -Content $syntheticMutation -Source 'fixture').Count -eq 1) `
    -Message 'Mutation scanner rejects a synthetic Agent 365 CLI invocation'

foreach ($mutationFixture in @(
    @{ Name = 'Agent 365 CLI version inspection'; Content = 'a365 --version' },
    @{ Name = 'Agent 365 native wrapper inspection'; Content = "Invoke-StaNativeCommand -FilePath 'a365' -ArgumentList @('--version')" },
    @{ Name = 'Unquoted native wrapper'; Content = 'Invoke-StaNativeCommand -FilePath a365 -ArgumentList @(setup, all)' },
    @{ Name = 'Variable native wrapper'; Content = '$target = ''a365''; Invoke-StaNativeCommand -FilePath $target -ArgumentList @(''--version'')' },
    @{ Name = 'Variable direct command'; Content = '$target = ''a365''; & $target --version' },
    @{ Name = 'Azure resource creation'; Content = 'az group create --name test --location eastus' },
    @{ Name = 'Agents Toolkit CLI version inspection'; Content = 'atk --version' },
    @{ Name = 'Agents Toolkit validation command'; Content = 'atk validate --env obo -i false' },
    @{ Name = 'Purview policy mutation'; Content = 'Set-FeatureConfiguration test' }
)) {
    Assert-ToolsCondition `
        -Condition (@(Find-StaForbiddenToolMutation -Content $mutationFixture.Content -Source 'fixture').Count -gt 0) `
        -Message "Mutation scanner rejects $($mutationFixture.Name)"
}

$syntheticPurviewMarker = '<PackageReference Include="Microsoft.Agents.AI.' + 'Purview" />'
Assert-ToolsCondition -Condition (@(Find-StaM0ImplementationMarker -Content $syntheticPurviewMarker -Source 'fixture').Count -eq 1) `
    -Message 'M0 scanner rejects a synthetic Purview package reference'

$secretFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "korea-expert-secret-fixture-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $secretFixtureRoot -Force | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $secretFixtureRoot '.env.dev') -Value 'AZURE_CLIENT_SECRET=not-a-real-secret-value'
    Set-Content -LiteralPath (Join-Path $secretFixtureRoot '.env.purview') -Value 'PURVIEW_GRAPH_ACCESS_TOKEN=not-a-real-access-token'
    Set-Content -LiteralPath (Join-Path $secretFixtureRoot 'settings.json') -Value '{"AzureClientSecret":"not-a-real-json-secret"}'
    $secretFindings = @(Find-StaPotentialSecrets -RepositoryRoot $secretFixtureRoot)
    Assert-ToolsCondition -Condition ($secretFindings.Count -eq 3) `
        -Message 'Secret scanner detects provider-prefixed .env and quoted JSON credentials'
}
finally {
    Remove-Item -LiteralPath $secretFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$placeholderFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "korea-expert-placeholder-fixture-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $placeholderFixtureRoot -Force | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $placeholderFixtureRoot '.env.dev') -Value 'CLIENT_SECRET=<set-in-user-environment>'
    Set-Content -LiteralPath (Join-Path $placeholderFixtureRoot 'settings.json') -Value '{"ClientSecret":"${CLIENT_SECRET}"}'
        Set-Content -LiteralPath (Join-Path $placeholderFixtureRoot 'compiled-template.json') -Value @'
{
    "outputs": {
        "connectionString": {
            "type": "string",
            "value": "[reference('resource').ConnectionString]"
        }
    }
}
'@
    New-Item -ItemType Directory -Path (Join-Path $placeholderFixtureRoot '.copilot-azure\session') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $placeholderFixtureRoot '.copilot-azure\session\what-if.json') `
        -Value 'human-readable what-if output'
    New-Item -ItemType Directory -Path (Join-Path $placeholderFixtureRoot '.azure\session') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $placeholderFixtureRoot '.azure\session\deployment.json') `
        -Value '{"AzureClientSecret":"protected-operational-fixture"}'
    $placeholderFindings = @(Find-StaPotentialSecrets -RepositoryRoot $placeholderFixtureRoot)
    Assert-ToolsCondition -Condition ($placeholderFindings.Count -eq 0) `
        -Message 'Secret scanner allows placeholders and excludes protected operational evidence'
}
finally {
    Remove-Item -LiteralPath $placeholderFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$dependencyFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "korea-expert-dependency-fixture-$([guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path (Join-Path $dependencyFixtureRoot 'server\agent-host') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dependencyFixtureRoot 'server\node_modules\fake') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dependencyFixtureRoot 'node_modules\fake') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dependencyFixtureRoot 'server\agent-host\Host.cs') -Value 'public class Host {}'
    Set-Content -LiteralPath (Join-Path $dependencyFixtureRoot 'server\node_modules\fake\Purview.cs') `
        -Value 'Microsoft.Agents.AI.Purview'

    $firstPartySources = @(Get-StaFirstPartyFiles -Path (Join-Path $dependencyFixtureRoot 'server') -Extension @('.cs'))
    Assert-ToolsCondition -Condition ($firstPartySources.Count -eq 1 -and $firstPartySources[0].Name -eq 'Host.cs') `
        -Message 'First-party source scans exclude node_modules'
}
finally {
    Remove-Item -LiteralPath $dependencyFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$json = Write-StaValidationResults -Results $repositoryResults -OutputFormat Json
$parsedJson = $json | ConvertFrom-Json -Depth 20
Assert-ToolsCondition -Condition ($parsedJson.Summary.Failed -eq 0) `
    -Message 'Many-result JSON output is consumable'

$singleResult = @(New-StaValidationResult -Area 'SelfTest' -Check 'One' -Status 'Pass' -Message 'One result')
$singleJson = Write-StaValidationResults -Results $singleResult -OutputFormat Json | ConvertFrom-Json -Depth 20
Assert-ToolsCondition -Condition ($singleJson.Summary.Passed -eq 1 -and @(Get-StaValidationExitCode -Results $singleResult)[0] -eq 0) `
    -Message 'One-result JSON and exit code are consumable'

$emptyResults = @()
$emptyJson = Write-StaValidationResults -Results $emptyResults -OutputFormat Json | ConvertFrom-Json -Depth 20
Assert-ToolsCondition -Condition ($emptyJson.Summary.Passed -eq 0 -and (Get-StaValidationExitCode -Results $emptyResults) -eq 1) `
    -Message 'Zero-result JSON is consumable and fails closed'

$safeFailure = @(Invoke-StaValidationSafely -Check 'Synthetic failure' -Operation {
    throw 'sensitive-canary-message'
})
$safeFailureJson = Write-StaValidationResults -Results $safeFailure -OutputFormat Json | ConvertFrom-Json -Depth 20
Assert-ToolsCondition -Condition (
    $safeFailureJson.Summary.Failed -eq 1 `
        -and $safeFailureJson.Results[0].Data.ExceptionType `
        -and ($safeFailureJson | ConvertTo-Json -Depth 20) -notmatch 'sensitive-canary-message') `
    -Message 'Unexpected validation failures remain structured and sanitized'

$emptySuccess = Get-StaPurviewEnforcementResult -StatusCode 200 -Content '' -ExpectBlock
Assert-ToolsCondition -Condition ($emptySuccess.Status -eq 'Fail' -and -not $emptySuccess.Data.EnforcementEvidence) `
    -Message 'Empty HTTP 200 Purview response cannot satisfy enforcement evidence'

$processingErrorResponse = '{"policyActions":[],"processingErrors":[{"code":"SyntheticFailure"}]}'
$processingError = Get-StaPurviewEnforcementResult -StatusCode 200 -Content $processingErrorResponse
Assert-ToolsCondition -Condition ($processingError.Status -eq 'Fail' -and $processingError.Data.ProcessingErrorCount -eq 1) `
    -Message 'Purview processing errors fail enforcement validation'

$validMiddlewareOrder = '.WithPurview(credential, settings).UseFunctionInvocation().UseOpenTelemetry()'
$invalidMiddlewareOrder = '.UseFunctionInvocation().WithPurview(credential, settings).UseOpenTelemetry()'
$validMiddlewareOrderAfterUrl = @'
var endpoint = "https://graph.microsoft.com/v1.0/";
.WithPurview(credential, settings).UseFunctionInvocation().UseOpenTelemetry()
'@
Assert-ToolsCondition -Condition (Test-StaPurviewMiddlewareOrder -Source $validMiddlewareOrder) `
    -Message 'Purview middleware order accepts Purview then function invocation then telemetry'
Assert-ToolsCondition -Condition (-not (Test-StaPurviewMiddlewareOrder -Source $invalidMiddlewareOrder)) `
    -Message 'Purview middleware order rejects reordered middleware'
Assert-ToolsCondition -Condition (Test-StaPurviewMiddlewareOrder -Source $validMiddlewareOrderAfterUrl) `
    -Message 'Purview middleware order scanning preserves source after URL literals'

if ($failures.Count -gt 0) {
    Write-Error "$($failures.Count) tools self-test(s) failed."
    exit 1
}

Write-Output "All $assertionCount tools self-tests passed."
