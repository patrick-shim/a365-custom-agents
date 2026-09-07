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

$modulePath = Join-Path $RepositoryRoot 'tools\modules\JapanExpert.Validation\JapanExpert.Validation.psm1'
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

$milestone = Get-JexMilestoneState -RepositoryRoot $RepositoryRoot
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
    -not [string]::IsNullOrWhiteSpace($frontendContract.contractId) -and
    $frontendContract.contractVersion -match '^\d+\.\d+\.\d+$' -and
    @($frontendContract.frontends).Count -eq 2 -and
    @($frontendContract.frontends.route) -contains '/api/messages' -and
    @($frontendContract.frontends.route) -contains '/api/messages/obo') `
    -Message 'Frontend backend contract declares both protected routes'

$sourceLayout = Get-JexSourceLayout -RepositoryRoot $RepositoryRoot
Assert-ToolsCondition -Condition (@($sourceLayout.UnresolvedPaths).Count -eq 0) `
    -Message 'Source layout discovery resolves the solution, host, MCP, and test projects'

$repositoryResults = @(Test-JexRepositoryConfiguration -RepositoryRoot $RepositoryRoot)
Assert-ToolsCondition -Condition (@($repositoryResults | Where-Object Status -eq 'Fail').Count -eq 0) `
    -Message 'Repository validation has no failures'
foreach ($repositoryCheck in @('Two protected host routes', 'Frontend channel audience mapping')) {
    Assert-ToolsCondition -Condition (@($repositoryResults | Where-Object {
        $_.Check -eq $repositoryCheck -and $_.Status -eq 'Pass'
    }).Count -eq 1) -Message "$repositoryCheck validation passes"
}

function Get-SelfTestRelativePath {
    param([Parameter(Mandatory)][string] $Path)

    [IO.Path]::GetRelativePath($RepositoryRoot, $Path)
}

$repositoryBoundaryFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "japan-expert-repository-boundary-fixture-$([guid]::NewGuid())"
try {
    $layoutFixtureFiles = @(
        $sourceLayout.SolutionPath,
        $sourceLayout.AgentProjectPath,
        $sourceLayout.HostProjectPath,
        $sourceLayout.ProgramPath,
        $sourceLayout.ApplicationPath,
        $sourceLayout.HostSettingsPath,
        (Join-Path $sourceLayout.HostDirectory 'appsettings.Development.json'),
        $sourceLayout.OboExchangePath,
        $sourceLayout.FrontendIdentityBindingPath,
        $sourceLayout.InternalMcpOptionsPath,
        $sourceLayout.InternalMcpCatalogPath,
        (Join-Path $sourceLayout.HostDirectory 'PromptShieldGuard.cs'),
        (Join-Path $sourceLayout.HostDirectory 'PromptShieldToolContentEvaluator.cs'),
        $sourceLayout.McpAuthorizationPath,
        (Join-Path (Split-Path -Parent $sourceLayout.McpAuthorizationPath) ([IO.Path]::GetFileName((Get-ChildItem -LiteralPath (Split-Path -Parent $sourceLayout.McpAuthorizationPath) -Filter '*.csproj' | Select-Object -First 1).FullName))),
        $sourceLayout.HostTestsProjectPath,
        $sourceLayout.AuthorizationTestsPath,
        $sourceLayout.OboExchangeTestsPath,
        $sourceLayout.FrontendIdentityBindingTestsPath,
        $sourceLayout.ObservabilityTokenCacheTestsPath,
        $sourceLayout.InternalMcpCatalogTestsPath,
        $sourceLayout.McpAuthorizationTestsPath,
        (Join-Path (Split-Path -Parent $sourceLayout.McpAuthorizationTestsPath) ([IO.Path]::GetFileName((Get-ChildItem -LiteralPath (Split-Path -Parent $sourceLayout.McpAuthorizationTestsPath) -Filter '*.csproj' | Select-Object -First 1).FullName)))
    ) + @($sourceLayout.McpServiceProjects.Values)
    $repositoryBoundaryFixtureFiles = @(
        'Directory.Packages.props',
        'README.md',
        'docs\milestones\milestones.json',
        'contracts\frontend-backend-contract.json',
        'contracts\frontend-backend-contract.schema.json',
        'infra\main.bicep',
        'infra\modules\agent-host-container-app.bicep',
        'infra\modules\mcp-api-application.bicep',
        'infra\modules\attractions-mcp-container-app.bicep',
        'infra\modules\weather-mcp-container-app.bicep',
        'infra\modules\accommodation-mcp-container-app.bicep',
        'infra\modules\currency-mcp-container-app.bicep'
    ) + @($layoutFixtureFiles | ForEach-Object { Get-SelfTestRelativePath -Path $_ })
    foreach ($relativePath in $repositoryBoundaryFixtureFiles) {
        $destination = Join-Path $repositoryBoundaryFixtureRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot $relativePath) -Destination $destination
    }
    New-Item -ItemType Directory -Path (Join-Path $repositoryBoundaryFixtureRoot 'tools') -Force | Out-Null

    $boundaryBaselineResults = @(Test-JexRepositoryConfiguration -RepositoryRoot $repositoryBoundaryFixtureRoot)
    Assert-ToolsCondition -Condition (@($boundaryBaselineResults | Where-Object Status -eq 'Fail').Count -eq 0) `
        -Message 'Repository boundary fixture starts from a passing offline baseline'

    $hostSettingsRelative = Get-SelfTestRelativePath -Path $sourceLayout.HostSettingsPath
    $programRelative = Get-SelfTestRelativePath -Path $sourceLayout.ProgramPath
    $applicationRelative = Get-SelfTestRelativePath -Path $sourceLayout.ApplicationPath
    $oboExchangeRelative = Get-SelfTestRelativePath -Path $sourceLayout.OboExchangePath
    $internalMcpOptionsRelative = Get-SelfTestRelativePath -Path $sourceLayout.InternalMcpOptionsPath
    $internalMcpCatalogTestsRelative = Get-SelfTestRelativePath -Path $sourceLayout.InternalMcpCatalogTestsPath
    $promptShieldToolRelative = Get-SelfTestRelativePath -Path (
        Join-Path $sourceLayout.HostDirectory 'PromptShieldToolContentEvaluator.cs')
    $firstSchemaFingerprint = [regex]::Match(
        (Get-Content -LiteralPath $sourceLayout.InternalMcpOptionsPath -Raw),
        '"[A-F0-9]{64}"').Value

    $boundaryMutations = @(
        @{
            Name  = 'tool-result prompt-injection screening removal'
            Check = 'Prompt Shields fail-closed injection guard'
            Path  = $promptShieldToolRelative
            Old   = 'PromptShieldSurface.Document'
            New   = 'PromptShieldSurface.UserPrompt'
        },
        @{
            Name  = 'prompt shield evaluation failure swallowed'
            Check = 'Prompt Shields fail-closed injection guard'
            Path  = $applicationRelative
            Old   = '_promptShieldOptions.EvaluationFailureMessage'
            New   = '"continuing without screening"'
        },
        @{
            Name  = 'stale appsettings OBO connection setting'
            Check = 'OBO authorization configuration boundary'
            Path  = $hostSettingsRelative
            Old   = '"AzureBotOAuthConnectionName":'
            New   = ('"OBOConnectionName": "OboServiceConnection",' + [Environment]::NewLine +
                '            "AzureBotOAuthConnectionName":')
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
            Path  = $oboExchangeRelative
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
            Path  = $applicationRelative
            Old   = '[AgentIdentityAuthorizationScopes.InternalMcpDefault(_internalMcpOptions.Audience)]'
            New   = '[mcpScope]'
        },
        @{
            Name  = 'S2S observability endpoint removal'
            Check = 'App-only child observability'
            Path  = $programRelative
            Old   = 'options.Agent365.UseS2SEndpoint = true;'
            New   = 'options.Agent365.UseS2SEndpoint = false;'
        },
        @{
            Name  = 'authenticated frontend identity resolver removal'
            Check = 'Authenticated frontend identity binding'
            Path  = $applicationRelative
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
            Path  = $internalMcpOptionsRelative
            Old   = $firstSchemaFingerprint
            New   = '"STALE-SCHEMA-FINGERPRINT"'
        },
        @{
            Name  = 'unexpected-tool rejection test removal'
            Check = 'Canonical MCP schema fingerprints'
            Path  = $internalMcpCatalogTestsRelative
            Old   = 'RejectsUnexpectedToolBeforeModelExposure'
            New   = 'AllowsUnexpectedToolBeforeModelExposure'
        },
        @{
            Name  = 'nested-schema rejection test removal'
            Check = 'Canonical MCP schema fingerprints'
            Path  = $internalMcpCatalogTestsRelative
            Old   = 'RejectsAlteredNestedSchemaBeforeModelExposure'
            New   = 'AllowsAlteredNestedSchemaBeforeModelExposure'
        },
        @{
            Name  = 'non-local HTTPS requirement removal'
            Check = 'Production MCP HTTPS endpoint enforcement'
            Path  = $programRelative
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
            $mutationResults = @(Test-JexRepositoryConfiguration -RepositoryRoot $repositoryBoundaryFixtureRoot)
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

$deploymentResults = @(Test-JexDeploymentBoundary -RepositoryRoot $RepositoryRoot)
Assert-ToolsCondition -Condition (@($deploymentResults | Where-Object Status -eq 'Fail').Count -eq 0) `
    -Message 'Deployment boundary validation has no failures'
foreach ($deploymentCheck in @(
    'Milestone deployment policy',
    'Resource group deployment scope',
    'No resource group creation',
    'Approved resource group target',
    'Existing Foundry cross-group reference',
    'Japan Tourist Expert resource naming',
    'Cost and secret-store boundary',
    'Retired Seoul deployment names',
    'Compiled update template parity',
    'Deployment module references',
    'Active milestone documentation',
    'MCP provider configuration',
    'Provider configuration parity',
    'Agent 365 identity ownership',
    'Azure Bot and Direct Line boundary',
    'Foundry Responses protocol boundary',
    'Foundry runtime access boundary'
)) {
    Assert-ToolsCondition -Condition (@($deploymentResults | Where-Object {
        $_.Check -eq $deploymentCheck -and $_.Status -eq 'Pass'
    }).Count -eq 1) -Message "$deploymentCheck validation passes"
}

$providerSections = Get-JexMcpProviderSection -RepositoryRoot $RepositoryRoot
Assert-ToolsCondition -Condition (
    @($providerSections.Values | Where-Object { -not $_.Resolved }).Count -eq 0 -and
    @($providerSections.Values | Where-Object { @($_.ProviderSections).Count -eq 0 }).Count -eq 0) `
    -Message 'Every MCP service exposes at least one bound provider configuration section'
Assert-ToolsCondition -Condition (
    @($deploymentResults |
        Where-Object { $_.Check -eq 'MCP provider configuration' } |
        ForEach-Object { $_.Data.Settings } |
        Where-Object { $_.Retired }).Count -eq 0) `
    -Message 'No retired provider setting is deployed to any MCP service'

$deploymentPolicy = Get-JexDeploymentPolicy -RepositoryRoot $RepositoryRoot
Assert-ToolsCondition -Condition (
    $deploymentPolicy.ApprovedResourceGroup -eq 'rg-a365-custom-agents' -and
    $deploymentPolicy.FoundryResourceGroup -eq 'rg-ai-foundry' -and
    $deploymentPolicy.FoundryAccountName -eq 'a365-ai-foundry' -and
    $deploymentPolicy.ModelDeploymentName -eq 'gpt-5.6-sol' -and
    $deploymentPolicy.IsConsistent) `
    -Message 'Deployment policy matches the active milestone manifest'

$deploymentNames = @(Get-JexExpectedDeploymentNames -ResourceBaseName $deploymentPolicy.ResourceBaseName)
Assert-ToolsCondition -Condition (
    $deploymentNames.Count -eq 16 -and
    @($deploymentNames | Where-Object { $_.ResolvedName.Length -gt $_.MaximumLength }).Count -eq 0 -and
    @($deploymentNames | Where-Object { $_.ResolvedName -notmatch 'japanexpert' }).Count -eq 0) `
    -Message 'Every deterministic resource name is Japan Tourist Expert branded and within its Azure limit'

$deploymentFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "japan-expert-deployment-fixture-$([guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path $deploymentFixtureRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot 'infra') -Destination $deploymentFixtureRoot -Recurse
    New-Item -ItemType Directory -Path (Join-Path $deploymentFixtureRoot 'docs\milestones') -Force | Out-Null
    Copy-Item `
        -LiteralPath (Join-Path $RepositoryRoot 'docs\milestones\milestones.json') `
        -Destination (Join-Path $deploymentFixtureRoot 'docs\milestones\milestones.json')
    $fixtureMcpSettings = [ordered]@{}
    foreach ($mcpProject in $sourceLayout.McpServiceProjects.GetEnumerator()) {
        $projectDirectory = Split-Path -Parent $mcpProject.Value
        foreach ($fileName in @([IO.Path]::GetFileName($mcpProject.Value), 'appsettings.json')) {
            $sourceFile = Join-Path $projectDirectory $fileName
            $relativePath = Get-SelfTestRelativePath -Path $sourceFile
            $destination = Join-Path $deploymentFixtureRoot $relativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $sourceFile -Destination $destination
            if ($fileName -eq 'appsettings.json') {
                $fixtureMcpSettings[$mcpProject.Key] = $relativePath
            }
        }
    }
    foreach ($hostFile in @(
        $sourceLayout.HostProjectPath,
        (Join-Path $sourceLayout.HostDirectory 'AgentHostOptions.cs'),
        (Join-Path $sourceLayout.HostDirectory 'AgentIdentityTokenContext.cs')
    )) {
        $relativePath = Get-SelfTestRelativePath -Path $hostFile
        $destination = Join-Path $deploymentFixtureRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $hostFile -Destination $destination
    }

    $deploymentBaseline = @(Test-JexDeploymentBoundary -RepositoryRoot $deploymentFixtureRoot)
    Assert-ToolsCondition -Condition (@($deploymentBaseline | Where-Object Status -eq 'Fail').Count -eq 0) `
        -Message 'Deployment fixture starts from a passing offline baseline'

    $deploymentMutations = @(
        @{
            Name  = 'earlier milestone presented as current guidance'
            Check = 'Active milestone documentation'
            Path  = 'infra\README.md'
            Old   = '> M8 is active.'
            New   = '> M7 is active.'
        },
        @{
            Name  = 'orphan infrastructure module'
            Check = 'Deployment module references'
            Path  = 'infra\modules\host-managed-identity.bicep'
            Old   = 'param identityName string'
            New   = 'param identityName string'
            ExtraFile = @{
                Path    = 'infra\modules\retired-key-vault.bicep'
                Content = "param vaultName string`noutput name string = vaultName`n"
            }
        },
        @{
            Name  = 'Key Vault without a source secret consumer'
            Check = 'Cost and secret-store boundary'
            Path  = 'infra\modules\container-registry.bicep'
            Old   = "resource registry 'Microsoft.ContainerRegistry/registries@2025-11-01' = {"
            New   = ("resource strayVault 'Microsoft.KeyVault/vaults@2026-02-01' existing = {" + [Environment]::NewLine +
                '  name: ' + [char]39 + 'stray' + [char]39 + [Environment]::NewLine +
                '}' + [Environment]::NewLine +
                [Environment]::NewLine +
                "resource registry 'Microsoft.ContainerRegistry/registries@2025-11-01' = {")
        },
        @{
            Name  = 'subscription-scope bootstrap'
            Check = 'Resource group deployment scope'
            Path  = 'infra\main.bicep'
            Old   = "targetScope = 'resourceGroup'"
            New   = "targetScope = 'subscription'"
        },
        @{
            Name  = 'resource group creation'
            Check = 'No resource group creation'
            Path  = 'infra\main.bicep'
            Old   = 'module logAnalytics '
            New   = ("resource createdGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {" + [Environment]::NewLine +
                "  name: 'rg-japanexpert-new'" + [Environment]::NewLine +
                '  location: location' + [Environment]::NewLine +
                '}' + [Environment]::NewLine +
                [Environment]::NewLine +
                'module logAnalytics ')
        },
        @{
            Name  = 'unapproved resource group target'
            Check = 'Approved resource group target'
            Path  = 'infra\main.bicep'
            Old   = "param foundryResourceGroupName string = 'rg-ai-foundry'"
            New   = "param foundryResourceGroupName string = 'rg-some-other-group'"
        },
        @{
            Name  = 'recreated Foundry account'
            Check = 'Existing Foundry cross-group reference'
            Path  = 'infra\main.bicep'
            Old   = "resource existingFoundryAccount 'Microsoft.CognitiveServices/accounts@2026-05-01' existing = {"
            New   = "resource existingFoundryAccount 'Microsoft.CognitiveServices/accounts@2026-05-01' = {"
        },
        @{
            Name  = 'non-deterministic resource name default'
            Check = 'Japan Tourist Expert resource naming'
            Path  = 'infra\main.bicep'
            Old   = 'param hostAppName string = ''ca-agent-${resourceBaseName}'''
            New   = 'param hostAppName string = ''ca-agent-unpinned'''
        },
        @{
            Name  = 'Premium registry default'
            Check = 'Cost and secret-store boundary'
            Path  = 'infra\main.bicep'
            Old   = "param containerRegistrySkuName string = 'Basic'"
            New   = "param containerRegistrySkuName string = 'Premium'"
        },
        @{
            Name  = 'scaled public-provider MCP service'
            Check = 'Cost and secret-store boundary'
            Path  = 'infra\modules\attractions-mcp-container-app.bicep'
            Old   = 'maxReplicas: 1'
            New   = 'maxReplicas: 3'
        },
        @{
            Name  = 'unused Key Vault resource'
            Check = 'Cost and secret-store boundary'
            Path  = 'infra\main.bicep'
            Old   = 'module logAnalytics '
            New   = ("resource staleVault 'Microsoft.KeyVault/vaults@2024-11-01' = {" + [Environment]::NewLine +
                "  name: 'kv-japanexpert'" + [Environment]::NewLine +
                '  location: location' + [Environment]::NewLine +
                '}' + [Environment]::NewLine +
                [Environment]::NewLine +
                'module logAnalytics ')
        },
        @{
            Name  = 'retired Seoul deployment name'
            Check = 'Retired Seoul deployment names'
            Path  = 'infra\main.parameters.json'
            Old   = '"value": "japanexpert"'
            New   = '"value": "seoultour-dev-kc-ae23"'
        },
        @{
            Name  = 'compiled update template drift'
            Check = 'Compiled update template parity'
            Path  = 'infra\live-backend-container-apps-update.bicep'
            Old   = 'param hostImage string'
            New   = 'param hostImageReference string'
        },
        @{
            Name  = 'plaintext provider endpoint'
            Check = 'MCP provider configuration'
            Path  = 'infra\live-backend-container-apps-update.json'
            Old   = '"defaultValue": "https://overpass-api.de/api/interpreter"'
            New   = '"defaultValue": "http://overpass-api.de/api/interpreter"'
        },
        @{
            Name  = 'committed mailbox in the provider User-Agent'
            Check = 'MCP provider configuration'
            Path  = 'infra\live-backend-container-apps-update.json'
            Old   = '"defaultValue": "JapanExpertMcp/1.0 (+https://github.com/patrick-shim/rg-a365-custom-agents)"'
            New   = '"defaultValue": "JapanExpertMcp/1.0 (mailto:operator@contoso.com)"'
        },
        @{
            Name  = 'provider section the deployment does not configure'
            Check = 'MCP provider configuration'
            Path  = $fixtureMcpSettings['weather']
            Old   = '"MetNorway"'
            New   = '"MetNorwayV3"'
        },
        @{
            Name  = 'provider default drift between templates'
            Check = 'Provider configuration parity'
            Path  = 'infra\live-backend-container-apps-update.bicep'
            Old   = "name: 'Overpass__Endpoint'"
            New   = "name: 'Overpass__InterpreterEndpoint'"
        },
        @{
            Name  = 'Bicep-owned Blueprint federated credential'
            Check = 'Agent 365 identity ownership'
            Path  = 'infra\modules\mcp-api-application.bicep'
            Old   = 'resource mcpApiServicePrincipal'
            New   = ("resource blueprintCredential 'Microsoft.Graph/applications/federatedIdentityCredentials@v1.0' = {" + [Environment]::NewLine +
                '  name: ' + [char]39 + 'host-uami' + [char]39 + [Environment]::NewLine +
                '}' + [Environment]::NewLine +
                [Environment]::NewLine +
                'resource mcpApiServicePrincipal')
        },
        @{
            Name  = 'removed host principal ID handoff output'
            Check = 'Agent 365 identity ownership'
            Path  = 'infra\main.bicep'
            Old   = 'output hostManagedIdentityPrincipalId string ='
            New   = 'output hostIdentityPrincipal string ='
        },
        @{
            Name  = 'undocumented Blueprint credential audience'
            Check = 'Agent 365 identity ownership'
            Path  = 'infra\README.md'
            Old   = 'api://AzureADTokenExchange'
            New   = 'api://SomeOtherExchange'
        },
        @{
            Name  = 'missing Blueprint credential rollback'
            Check = 'Agent 365 identity ownership'
            Path  = 'infra\README.md'
            Old   = 'az rest --method DELETE'
            New   = 'az rest --method PATCH'
        },
        @{
            Name  = 'bot endpoint moved off the protected OBO route'
            Check = 'Azure Bot and Direct Line boundary'
            Path  = 'infra\main.bicep'
            Old   = '/api/messages/obo'
            New   = '/api/messages'
        },
        @{
            Name  = 'published Direct Line channel secret'
            Check = 'Azure Bot and Direct Line boundary'
            Path  = 'infra\modules\azure-bot.bicep'
            Old   = 'output messagingEndpoint string = bot.properties.endpoint'
            New   = ('output messagingEndpoint string = bot.properties.endpoint' + [Environment]::NewLine +
                'output directLineSecret string = listChannelWithKeys(bot.id, ' + [char]39 + '2022-09-15' + [char]39 + ').properties.properties.sites[0].key')
        },
        @{
            Name  = 'Direct Line v3 disabled'
            Check = 'Azure Bot and Direct Line boundary'
            Path  = 'infra\modules\azure-bot.bicep'
            Old   = 'isV3Enabled: true'
            New   = 'isV3Enabled: false'
        },
        @{
            Name  = 'Microsoft Teams channel removed'
            Check = 'Azure Bot and Direct Line boundary'
            Path  = 'infra\modules\azure-bot.bicep'
            Old   = "channelName: 'MsTeamsChannel'"
            New   = "channelName: 'SlackChannel'"
        },
        @{
            Name  = 'retired account-root Foundry host setting'
            Check = 'Foundry Responses protocol boundary'
            Path  = 'infra\modules\agent-host-container-app.bicep'
            Old   = "name: 'AgentHost__FoundryProjectEndpoint'"
            New   = "name: 'AgentHost__AzureOpenAIEndpoint'"
        },
        @{
            Name  = 'host setting outside the options contract'
            Check = 'Foundry Responses protocol boundary'
            Path  = 'infra\modules\agent-host-container-app.bicep'
            Old   = "name: 'AgentHost__FoundryModelDeployment'"
            New   = "name: 'AgentHost__FoundryModelName'"
        },
        @{
            Name  = 'retired host setting in owned deployment documentation'
            Check = 'Foundry Responses protocol boundary'
            Path  = 'infra\README.md'
            Old   = '# Japan Tourist Expert backend infrastructure'
            New   = ('# Japan Tourist Expert backend infrastructure' + [Environment]::NewLine +
                [Environment]::NewLine +
                'Set AgentHost__AzureOpenAIEndpoint on the host.')
        },
        @{
            Name  = 'injected raw responses route'
            Check = 'Foundry Responses protocol boundary'
            Path  = 'infra\modules\agent-host-container-app.bicep'
            Old   = '    value: foundryProjectEndpoint'
            New   = "    value: '`${foundryProjectEndpoint}/openai/responses?api-version=2026-07-09'"
        },
        @{
            Name  = 'OAuth secure decorator removal'
            Check = 'Azure Bot and Direct Line boundary'
            Path  = 'infra\modules\azure-bot.bicep'
            Old   = '@secure()'
            New   = '// secure decorator removed'
        },
        @{
            Name  = 'Direct Line v1 re-enabled'
            Check = 'Azure Bot and Direct Line boundary'
            Path  = 'infra\modules\azure-bot.bicep'
            Old   = 'isV1Enabled: false'
            New   = 'isV1Enabled: true'
        },
        @{
            Name  = 'Teams channel removal'
            Check = 'Azure Bot and Direct Line boundary'
            Path  = 'infra\modules\azure-bot.bicep'
            Old   = "channelName: 'MsTeamsChannel'"
            New   = "channelName: 'WebChatChannel'"
        },
        @{
            Name  = 'unconditional Direct Line enhanced authentication'
            Check = 'Azure Bot and Direct Line boundary'
            Path  = 'infra\modules\azure-bot.bicep'
            Old   = 'isSecureSiteEnabled: !empty(directLineTrustedOrigins)'
            New   = 'isSecureSiteEnabled: true'
        },
        @{
            Name  = 'inference token scope drift from the host contract'
            Check = 'Foundry runtime access boundary'
            Path  = 'infra\modules\agent-host-container-app.bicep'
            Old   = "param foundryTokenScope string = 'https://ai.azure.com/.default'"
            New   = "param foundryTokenScope string = 'https://cognitiveservices.azure.com/.default'"
        },
        @{
            Name  = 'retired Foundry data-plane role claim'
            Check = 'Foundry runtime access boundary'
            Path  = 'infra\main.bicep'
            Old   = '// Japan Tourist Expert shared backend bootstrap.'
            New   = ('// Japan Tourist Expert shared backend bootstrap.' + [Environment]::NewLine +
                '// Grant Cognitive Services OpenAI User to each child identity.')
        }
    )
    foreach ($mutation in $deploymentMutations) {
        $mutationPath = Join-Path $deploymentFixtureRoot $mutation.Path
        $originalContent = Get-Content -LiteralPath $mutationPath -Raw
        $markerPresent = $originalContent.Contains($mutation.Old, [StringComparison]::Ordinal)
        Assert-ToolsCondition -Condition $markerPresent `
            -Message "Deployment fixture contains marker for $($mutation.Name)"
        if (-not $markerPresent) {
            continue
        }

        try {
            $originalContent.Replace($mutation.Old, $mutation.New) |
                Set-Content -LiteralPath $mutationPath -NoNewline
            $extraFilePath = ''
            if ($mutation.ContainsKey('ExtraFile')) {
                $extraFilePath = Join-Path $deploymentFixtureRoot $mutation.ExtraFile.Path
                New-Item -ItemType Directory -Path (Split-Path -Parent $extraFilePath) -Force | Out-Null
                Set-Content -LiteralPath $extraFilePath -Value $mutation.ExtraFile.Content -NoNewline
            }
            $mutationResults = @(Test-JexDeploymentBoundary -RepositoryRoot $deploymentFixtureRoot)
            Assert-ToolsCondition -Condition (@($mutationResults | Where-Object {
                $_.Check -eq $mutation.Check -and $_.Status -eq 'Fail'
            }).Count -eq 1) -Message "$($mutation.Check) rejects $($mutation.Name)"
            if ($extraFilePath) {
                Remove-Item -LiteralPath $extraFilePath -Force -ErrorAction SilentlyContinue
            }
        }
        finally {
            Set-Content -LiteralPath $mutationPath -Value $originalContent -NoNewline
        }
    }
}
finally {
    Remove-Item -LiteralPath $deploymentFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$azureResults = @(Test-JexAzureReadiness -RepositoryRoot $RepositoryRoot)
Assert-ToolsCondition -Condition (@($azureResults | Where-Object Status -eq 'Fail').Count -eq 0) `
    -Message 'Offline Azure validation has no failures'
Assert-ToolsCondition -Condition (@($azureResults | Where-Object { $_.Check -eq 'Azure account' -and $_.Status -eq 'Skip' }).Count -eq 1) `
    -Message 'Azure tenant calls are opt-in'
$unauthorizedAzureResults = @(Test-JexAzureReadiness `
    -RepositoryRoot $RepositoryRoot `
    -ResourceId '/subscriptions/test/resourceGroups/test/providers/Microsoft.Test/resources/test')
Assert-ToolsCondition -Condition (@($unauthorizedAzureResults | Where-Object { $_.Check -eq 'Online switch' -and $_.Status -eq 'Fail' }).Count -eq 1) `
    -Message 'Azure resource parameters fail without explicit online authorization'

$capabilityFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "japan-expert-capability-fixture-$([guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path (Join-Path $capabilityFixtureRoot 'docs\milestones') -Force | Out-Null
    $capabilityManifest = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'docs\milestones\milestones.json') -Raw |
        ConvertFrom-Json -Depth 20
    $capabilityManifest.milestones |
        Where-Object id -eq $capabilityManifest.currentMilestone |
        ForEach-Object { $_.allowsTenantReads = $false }
    $capabilityManifest | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath (Join-Path $capabilityFixtureRoot 'docs\milestones\milestones.json')
    $capabilityResults = @(Test-JexAzureReadiness -RepositoryRoot $capabilityFixtureRoot -Online)
    Assert-ToolsCondition -Condition (@($capabilityResults | Where-Object { $_.Check -eq 'Milestone tenant-read authorization' -and $_.Status -eq 'Fail' }).Count -eq 1) `
        -Message 'Milestone capability gate blocks online Azure reads'
}
finally {
    Remove-Item -LiteralPath $capabilityFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$purviewResults = @(Test-JexPurviewReadiness -RepositoryRoot $RepositoryRoot)
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

$invalidProbeResults = @(Test-JexPurviewReadiness -RepositoryRoot $RepositoryRoot -ProbePolicy)
Assert-ToolsCondition -Condition (@($invalidProbeResults | Where-Object { $_.Check -eq 'Online switch' -and $_.Status -eq 'Fail' }).Count -eq 1) `
    -Message 'Purview probes require explicit online authorization'

$toolMutationFindings = @($toolFiles | ForEach-Object {
    Find-JexForbiddenToolMutation `
        -Content (Get-Content -LiteralPath $_.FullName -Raw) `
        -Source ([IO.Path]::GetRelativePath($RepositoryRoot, $_.FullName))
})
Assert-ToolsCondition -Condition ($toolMutationFindings.Count -eq 0) `
    -Message 'Validation tools contain no disallowed cloud CLI commands'

$syntheticMutation = 'a365 --version'
Assert-ToolsCondition -Condition (@(Find-JexForbiddenToolMutation -Content $syntheticMutation -Source 'fixture').Count -eq 1) `
    -Message 'Mutation scanner rejects a synthetic Agent 365 CLI invocation'

foreach ($mutationFixture in @(
    @{ Name = 'Agent 365 CLI version inspection'; Content = 'a365 --version' },
    @{ Name = 'Agent 365 native wrapper inspection'; Content = "Invoke-JexNativeCommand -FilePath 'a365' -ArgumentList @('--version')" },
    @{ Name = 'Unquoted native wrapper'; Content = 'Invoke-JexNativeCommand -FilePath a365 -ArgumentList @(setup, all)' },
    @{ Name = 'Variable native wrapper'; Content = '$target = ''a365''; Invoke-JexNativeCommand -FilePath $target -ArgumentList @(''--version'')' },
    @{ Name = 'Variable direct command'; Content = '$target = ''a365''; & $target --version' },
    @{ Name = 'Azure resource creation'; Content = 'az group create --name test --location eastus' },
    @{ Name = 'Agents Toolkit CLI version inspection'; Content = 'atk --version' },
    @{ Name = 'Agents Toolkit validation command'; Content = 'atk validate --env obo -i false' },
    @{ Name = 'Purview policy mutation'; Content = 'Set-FeatureConfiguration test' }
)) {
    Assert-ToolsCondition `
        -Condition (@(Find-JexForbiddenToolMutation -Content $mutationFixture.Content -Source 'fixture').Count -gt 0) `
        -Message "Mutation scanner rejects $($mutationFixture.Name)"
}

$syntheticPurviewMarker = '<PackageReference Include="Microsoft.Agents.AI.' + 'Purview" />'
Assert-ToolsCondition -Condition (@(Find-JexM0ImplementationMarker -Content $syntheticPurviewMarker -Source 'fixture').Count -eq 1) `
    -Message 'M0 scanner rejects a synthetic Purview package reference'

$secretFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "japan-expert-secret-fixture-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $secretFixtureRoot -Force | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $secretFixtureRoot '.env.dev') -Value 'AZURE_CLIENT_SECRET=not-a-real-secret-value'
    Set-Content -LiteralPath (Join-Path $secretFixtureRoot '.env.purview') -Value 'PURVIEW_GRAPH_ACCESS_TOKEN=not-a-real-access-token'
    Set-Content -LiteralPath (Join-Path $secretFixtureRoot 'settings.json') -Value '{"AzureClientSecret":"not-a-real-json-secret"}'
    $secretFindings = @(Find-JexPotentialSecrets -RepositoryRoot $secretFixtureRoot)
    Assert-ToolsCondition -Condition ($secretFindings.Count -eq 3) `
        -Message 'Secret scanner detects provider-prefixed .env and quoted JSON credentials'
}
finally {
    Remove-Item -LiteralPath $secretFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$placeholderFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "japan-expert-placeholder-fixture-$([guid]::NewGuid())"
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
    $placeholderFindings = @(Find-JexPotentialSecrets -RepositoryRoot $placeholderFixtureRoot)
    Assert-ToolsCondition -Condition ($placeholderFindings.Count -eq 0) `
        -Message 'Secret scanner allows placeholders and excludes protected operational evidence'
}
finally {
    Remove-Item -LiteralPath $placeholderFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$identifierFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "japan-expert-identifier-fixture-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $identifierFixtureRoot -Force | Out-Null
try {
    # Fixture identifiers are generated at run time so this test file never itself carries an
    # identifier-shaped literal that the scanner would have to exempt.
    $fixtureSubscription = [guid]::NewGuid().ToString()
    $fixtureTenant = [guid]::NewGuid().ToString()
    $fixtureResourceGroupId = [guid]::NewGuid().ToString()
    $fixturePrincipal = [guid]::NewGuid().ToString()
    $fixtureMailbox = 'first.last' + [char]64 + 'fabrikam.io'
    Set-Content -LiteralPath (Join-Path $identifierFixtureRoot 'committed.json') -Value @"
{
  "subscriptionId": "$fixtureSubscription",
  "tenantId": "$fixtureTenant",
  "scope": "/subscriptions/$fixtureResourceGroupId/resourceGroups/rg-x/providers/Microsoft.App/containerApps/ca-x",
  "owner": "$fixtureMailbox"
}
"@
    Set-Content -LiteralPath (Join-Path $identifierFixtureRoot 'grant.ps1') `
        -Value "az role assignment create --assignee-object-id $fixturePrincipal"
    $identifierFindings = @(Find-JexCommittedIdentifier -RepositoryRoot $identifierFixtureRoot)
    $identifierRules = @($identifierFindings.Rule | Sort-Object -Unique)
    Assert-ToolsCondition -Condition (
        $identifierRules -contains 'Subscription ID' -and
        $identifierRules -contains 'Tenant or directory ID' -and
        $identifierRules -contains 'Principal or object ID' -and
        $identifierRules -contains 'Full ARM resource ID' -and
        $identifierRules -contains 'User principal name or mailbox') `
        -Message 'Identifier scanner rejects committed subscription, tenant, principal, resource ID, and mailbox values'
    Assert-ToolsCondition -Condition (
        @($identifierFindings | Where-Object {
            ($_ | ConvertTo-Json -Compress) -match '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}'
        }).Count -eq 0) `
        -Message 'Identifier findings report location and rule without echoing the value'
}
finally {
    Remove-Item -LiteralPath $identifierFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$identifierSafeFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "japan-expert-identifier-safe-fixture-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $identifierSafeFixtureRoot -Force | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $identifierSafeFixtureRoot 'runbook.md') -Value @'
$subscriptionId = '<subscription-id>'
$tenantId = '<entra-tenant-id>'
az role assignment create --assignee-object-id '<child-principal-id>' `
  --scope "/subscriptions/$subscriptionId/resourceGroups/rg-a365-custom-agents/providers/Microsoft.CognitiveServices/accounts/a365-ai-foundry"
Contact the operator at ops@contoso.com for approval.
'@
    Set-Content -LiteralPath (Join-Path $identifierSafeFixtureRoot 'roles.bicep') -Value @'
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var blueprintIngressScope = '5a807f24-c9de-44ee-a3a7-329e88a00ffc/.default'
param tenantId string
output scope string = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
'@
    Set-Content -LiteralPath (Join-Path $identifierSafeFixtureRoot 'unit-test.cs') -Value @'
private const string TenantId = "11111111-1111-4111-8111-111111111111";
private const string SubscriptionId = "00000000-0000-0000-0000-000000000000";
'@
    $safeIdentifierFindings = @(Find-JexCommittedIdentifier -RepositoryRoot $identifierSafeFixtureRoot)
    Assert-ToolsCondition -Condition ($safeIdentifierFindings.Count -eq 0) `
        -Message 'Identifier scanner allows placeholders, well-known role and resource app IDs, synthetic test GUIDs, and example mailboxes'
}
finally {
    Remove-Item -LiteralPath $identifierSafeFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$syntheticCaseFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "japan-expert-synthetic-case-fixture-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $syntheticCaseFixtureRoot -Force | Out-Null
try {
    # Values are generated at run time so this test file never itself carries a sensitive-data literal.
    $cardBody = '4' + ('0' * 14)
    $cardCheckDigit = 0
    for ($candidate = 0; $candidate -le 9; $candidate++) {
        $sum = 0
        $alternate = $false
        $digits = "$cardBody$candidate"
        for ($index = $digits.Length - 1; $index -ge 0; $index--) {
            $digit = [int][string]$digits[$index]
            if ($alternate) {
                $digit *= 2
                if ($digit -gt 9) { $digit -= 9 }
            }
            $sum += $digit
            $alternate = -not $alternate
        }
        if (($sum % 10) -eq 0) {
            $cardCheckDigit = $candidate
            break
        }
    }
    $unreservedPassport = 'AB' + '1234567'
    $unreservedResidence = 'CD' + '12345678' + 'EF'
    Set-Content -LiteralPath (Join-Path $syntheticCaseFixtureRoot 'cases.md') -Value @"
card $cardBody$cardCheckDigit
passport $unreservedPassport
residence $unreservedResidence
"@
    $syntheticFindings = @(Find-JexSyntheticSensitiveData -RepositoryRoot $syntheticCaseFixtureRoot)
    $syntheticRules = @($syntheticFindings.Rule | Sort-Object -Unique)
    Assert-ToolsCondition -Condition (
        $syntheticRules -contains 'Card-shaped checksum-valid number' -and
        $syntheticRules -contains 'Passport-shaped literal outside the reserved range' -and
        $syntheticRules -contains 'Residence-card-shaped literal outside the reserved range') `
        -Message 'Synthetic data scanner rejects card, passport, and residence-card literals outside the reserved ranges'
    Assert-ToolsCondition -Condition (
        @($syntheticFindings | Where-Object {
            ($_ | ConvertTo-Json -Compress) -match '[0-9]{7,}'
        }).Count -eq 0) `
        -Message 'Synthetic data findings report location and rule without echoing the value'
}
finally {
    Remove-Item -LiteralPath $syntheticCaseFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$reservedCaseFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "japan-expert-reserved-case-fixture-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $reservedCaseFixtureRoot -Force | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $reservedCaseFixtureRoot 'reserved.md') -Value @"
Japan passport uses the reserved prefix: $('ZZ' + '1234567')
Japanese residence card uses the reserved prefix: $('ZZ' + '12345678' + 'ZZ')
The exact reserved test card value stays in the Direct Line frontend fixture.
"@
    Set-Content -LiteralPath (Join-Path $reservedCaseFixtureRoot 'compiled.json') -Value @'
{ "metadata": { "_generator": { "templateHash": "1513497685527020944" } } }
'@
    $reservedFindings = @(Find-JexSyntheticSensitiveData -RepositoryRoot $reservedCaseFixtureRoot)
    Assert-ToolsCondition -Condition ($reservedFindings.Count -eq 0) `
        -Message 'Synthetic data scanner allows reserved-prefix cases and generated template hashes'
}
finally {
    Remove-Item -LiteralPath $reservedCaseFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$casePolicy = Get-JexSyntheticCasePolicy -RepositoryRoot $RepositoryRoot
Assert-ToolsCondition -Condition (
    @($casePolicy.ExpectedCases).Count -eq 3 -and
    @($casePolicy.MissingCases).Count -eq 0 -and
    @($casePolicy.RetiredDeclared).Count -eq 0 -and
    $casePolicy.IsConsistent) `
    -Message 'The active milestone declares exactly the three reserved synthetic Purview cases'

$retiredSymbolFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "japan-expert-symbol-fixture-$([guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path (Join-Path $retiredSymbolFixtureRoot 'tools') -Force | Out-Null
    $retiredPrefix = 'Sta'
    Set-Content -LiteralPath (Join-Path $retiredSymbolFixtureRoot 'tools\Legacy.ps1') -Value @"
function New-${retiredPrefix}ValidationResult { }
New-${retiredPrefix}ValidationResult
"@
    $retiredSymbolFindings = @(Find-JexRetiredSymbol -RepositoryRoot $retiredSymbolFixtureRoot)
    $retiredSymbolRules = @($retiredSymbolFindings.Rule | Sort-Object -Unique)
    Assert-ToolsCondition -Condition (
        $retiredSymbolRules -contains 'retired product acronym' -and
        $retiredSymbolRules -contains 'function outside the Jex prefix') `
        -Message 'Symbol scanner rejects a retired product acronym and a non-Jex function definition'

    Set-Content -LiteralPath (Join-Path $retiredSymbolFixtureRoot 'tools\Current.ps1') -Value @'
function Test-JexExample { }
$twoStage = 'Two-stage child Agent Identity OBO'
$stayName = 'id-stay-japanexpert'
'@
    Remove-Item -LiteralPath (Join-Path $retiredSymbolFixtureRoot 'tools\Legacy.ps1') -Force
    $currentSymbolFindings = @(Find-JexRetiredSymbol -RepositoryRoot $retiredSymbolFixtureRoot)
    Assert-ToolsCondition -Condition ($currentSymbolFindings.Count -eq 0) `
        -Message 'Symbol scanner allows Jex functions and English or resource names that merely contain "sta"'
}
finally {
    Remove-Item -LiteralPath $retiredSymbolFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$dependencyFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "japan-expert-dependency-fixture-$([guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path (Join-Path $dependencyFixtureRoot 'server\agent-host') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dependencyFixtureRoot 'server\node_modules\fake') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dependencyFixtureRoot 'node_modules\fake') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dependencyFixtureRoot 'server\agent-host\Host.cs') -Value 'public class Host {}'
    Set-Content -LiteralPath (Join-Path $dependencyFixtureRoot 'server\node_modules\fake\Purview.cs') `
        -Value 'Microsoft.Agents.AI.Purview'

    $firstPartySources = @(Get-JexFirstPartyFiles -Path (Join-Path $dependencyFixtureRoot 'server') -Extension @('.cs'))
    Assert-ToolsCondition -Condition ($firstPartySources.Count -eq 1 -and $firstPartySources[0].Name -eq 'Host.cs') `
        -Message 'First-party source scans exclude node_modules'
}
finally {
    Remove-Item -LiteralPath $dependencyFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$json = Write-JexValidationResults -Results $repositoryResults -OutputFormat Json
$parsedJson = $json | ConvertFrom-Json -Depth 20
Assert-ToolsCondition -Condition ($parsedJson.Summary.Failed -eq 0) `
    -Message 'Many-result JSON output is consumable'

$singleResult = @(New-JexValidationResult -Area 'SelfTest' -Check 'One' -Status 'Pass' -Message 'One result')
$singleJson = Write-JexValidationResults -Results $singleResult -OutputFormat Json | ConvertFrom-Json -Depth 20
Assert-ToolsCondition -Condition ($singleJson.Summary.Passed -eq 1 -and @(Get-JexValidationExitCode -Results $singleResult)[0] -eq 0) `
    -Message 'One-result JSON and exit code are consumable'

$emptyResults = @()
$emptyJson = Write-JexValidationResults -Results $emptyResults -OutputFormat Json | ConvertFrom-Json -Depth 20
Assert-ToolsCondition -Condition ($emptyJson.Summary.Passed -eq 0 -and (Get-JexValidationExitCode -Results $emptyResults) -eq 1) `
    -Message 'Zero-result JSON is consumable and fails closed'

$safeFailure = @(Invoke-JexValidationSafely -Check 'Synthetic failure' -Operation {
    throw 'sensitive-canary-message'
})
$safeFailureJson = Write-JexValidationResults -Results $safeFailure -OutputFormat Json | ConvertFrom-Json -Depth 20
Assert-ToolsCondition -Condition (
    $safeFailureJson.Summary.Failed -eq 1 `
        -and $safeFailureJson.Results[0].Data.ExceptionType `
        -and ($safeFailureJson | ConvertTo-Json -Depth 20) -notmatch 'sensitive-canary-message') `
    -Message 'Unexpected validation failures remain structured and sanitized'

$emptySuccess = Get-JexPurviewEnforcementResult -StatusCode 200 -Content '' -ExpectBlock
Assert-ToolsCondition -Condition ($emptySuccess.Status -eq 'Fail' -and -not $emptySuccess.Data.EnforcementEvidence) `
    -Message 'Empty HTTP 200 Purview response cannot satisfy enforcement evidence'

$processingErrorResponse = '{"policyActions":[],"processingErrors":[{"code":"SyntheticFailure"}]}'
$processingError = Get-JexPurviewEnforcementResult -StatusCode 200 -Content $processingErrorResponse
Assert-ToolsCondition -Condition ($processingError.Status -eq 'Fail' -and $processingError.Data.ProcessingErrorCount -eq 1) `
    -Message 'Purview processing errors fail enforcement validation'

$validMiddlewareOrder = '.WithPurview(credential, settings).UseFunctionInvocation().UseOpenTelemetry()'
$invalidMiddlewareOrder = '.UseFunctionInvocation().WithPurview(credential, settings).UseOpenTelemetry()'
$validMiddlewareOrderAfterUrl = @'
var endpoint = "https://graph.microsoft.com/v1.0/";
.WithPurview(credential, settings).UseFunctionInvocation().UseOpenTelemetry()
'@
Assert-ToolsCondition -Condition (Test-JexPurviewMiddlewareOrder -Source $validMiddlewareOrder) `
    -Message 'Purview middleware order accepts Purview then function invocation then telemetry'
Assert-ToolsCondition -Condition (-not (Test-JexPurviewMiddlewareOrder -Source $invalidMiddlewareOrder)) `
    -Message 'Purview middleware order rejects reordered middleware'
Assert-ToolsCondition -Condition (Test-JexPurviewMiddlewareOrder -Source $validMiddlewareOrderAfterUrl) `
    -Message 'Purview middleware order scanning preserves source after URL literals'

if ($failures.Count -gt 0) {
    Write-Error "$($failures.Count) tools self-test(s) failed."
    exit 1
}

Write-Output "All $assertionCount tools self-tests passed."
