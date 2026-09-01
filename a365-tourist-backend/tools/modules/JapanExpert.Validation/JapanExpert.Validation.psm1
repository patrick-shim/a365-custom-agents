Set-StrictMode -Version Latest

$script:DefaultRepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

function New-JexValidationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Area,

        [Parameter(Mandatory)]
        [string] $Check,

        [Parameter(Mandatory)]
        [ValidateSet('Pass', 'Warn', 'Fail', 'Skip')]
        [string] $Status,

        [Parameter(Mandatory)]
        [string] $Message,

        [string] $Remediation = '',

        [AllowNull()]
        [object] $Data = $null
    )

    [pscustomobject][ordered]@{
        Area        = $Area
        Check       = $Check
        Status      = $Status
        Message     = $Message
        Remediation = $Remediation
        Data        = $Data
    }
}

function Invoke-JexValidationSafely {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $Operation,

        [Parameter(Mandatory)]
        [string] $Check
    )

    try {
        @($Operation.Invoke())
    }
    catch {
        New-JexValidationResult `
            -Area 'Tooling' `
            -Check $Check `
            -Status 'Fail' `
            -Message 'Validation could not complete because of an unexpected local error.' `
            -Remediation 'Review local paths and configuration, then rerun the command.' `
            -Data @{ ExceptionType = $_.Exception.GetType().FullName }
    }
}

function Resolve-JexRepositoryRoot {
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    if (-not (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) {
        throw "Repository root does not exist: $RepositoryRoot"
    }

    (Resolve-Path -LiteralPath $RepositoryRoot).Path
}

function Invoke-JexNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [string[]] $ArgumentList = @(),

        [string] $WorkingDirectory = ''
    )

    $previousLocation = $null
    try {
        if ($WorkingDirectory) {
            $previousLocation = Get-Location
            Set-Location -LiteralPath $WorkingDirectory
        }

        $commandOutput = & $FilePath @ArgumentList 2>&1
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
        [pscustomobject]@{
            ExitCode = $exitCode
            Output   = ($commandOutput | Out-String).Trim()
        }
    }
    catch {
        [pscustomobject]@{
            ExitCode = -1
            Output   = $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $previousLocation) {
            Set-Location -LiteralPath $previousLocation
        }
    }
}

function ConvertTo-JexVersion {
    [CmdletBinding()]
    param([AllowEmptyString()][string] $Value)

    $match = [regex]::Match($Value, '\d+(?:\.\d+){1,3}')
    if (-not $match.Success) {
        return $null
    }

    try {
        [version]$match.Value
    }
    catch {
        $null
    }
}

function Get-JexJwtContext {
    [CmdletBinding()]
    param([AllowEmptyString()][string] $Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return @{}
    }

    try {
        $segments = $Token.Split('.')
        if ($segments.Count -lt 2) {
            return @{}
        }
        $payload = $segments[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) {
            2 { $payload += '==' }
            3 { $payload += '=' }
        }
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) |
            ConvertFrom-Json -Depth 10
        @{
            TenantId    = $claims.tid
            ClientId    = if ($claims.azp) { $claims.azp } else { $claims.appid }
            TokenObject = $claims.oid
        }
    }
    catch {
        @{}
    }
}

function Find-JexM0ImplementationMarker {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string] $Content,
        [string] $Source = 'input'
    )

    $patterns = [ordered]@{
        'Purview package or middleware' = 'Microsoft\.Agents\.AI\.Purview|\.WithPurview\s*\('
        'Agent 365 notifications'        = 'Microsoft\.Agents\.A365\.Notifications'
        'Agent 365 observability'        = 'Microsoft\.Agents\.A365\.Observability|UseMicrosoftOpenTelemetry'
    }
    foreach ($entry in $patterns.GetEnumerator()) {
        if ([regex]::IsMatch($Content, $entry.Value, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            [pscustomobject]@{ Source = $Source; Marker = $entry.Key }
        }
    }
}

function Find-JexForbiddenToolMutation {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string] $Content,
        [string] $Source = 'input'
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput(
        $Content,
        [ref]$tokens,
        [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        [pscustomobject]@{ Source = $Source; Mutation = 'Unparseable PowerShell'; Command = '' }
        return
    }

    $commands = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst]
    }, $true))

    function Get-JexContainingFunctionName {
        param([Management.Automation.Language.Ast] $Node)

        $current = $Node.Parent
        while ($null -ne $current) {
            if ($current -is [Management.Automation.Language.FunctionDefinitionAst]) {
                return $current.Name
            }
            $current = $current.Parent
        }
        ''
    }

    function Get-JexNamedArgumentAst {
        param(
            [Management.Automation.Language.CommandAst] $Command,
            [string] $ParameterName
        )

        for ($index = 0; $index -lt $Command.CommandElements.Count; $index++) {
            $element = $Command.CommandElements[$index]
            if ($element -is [Management.Automation.Language.CommandParameterAst] -and
                $element.ParameterName -eq $ParameterName -and
                $index + 1 -lt $Command.CommandElements.Count) {
                return $Command.CommandElements[$index + 1]
            }
        }
        $null
    }

    function Get-JexConstantString {
        param([AllowNull()][Management.Automation.Language.Ast] $Node)

        if ($null -eq $Node) {
            return $null
        }
        if ($Node -is [Management.Automation.Language.StringConstantExpressionAst]) {
            return $Node.Value
        }
        if ($Node -is [Management.Automation.Language.ExpandableStringExpressionAst] -and
            $Node.NestedExpressions.Count -eq 0) {
            return $Node.Value
        }
        $null
    }

    function Get-JexLiteralArgumentStrings {
        param([AllowNull()][Management.Automation.Language.Ast] $Node)

        if ($null -eq $Node) {
            return @()
        }
        @($Node.FindAll({
            param($child)
            $child -is [Management.Automation.Language.StringConstantExpressionAst] -or
                ($child -is [Management.Automation.Language.ExpandableStringExpressionAst] -and
                    $child.NestedExpressions.Count -eq 0)
        }, $true) | ForEach-Object { $_.Value })
    }

    foreach ($command in $commands) {
        $commandName = $command.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($commandName)) {
            $containingFunction = Get-JexContainingFunctionName -Node $command
            if ($containingFunction -ne 'Invoke-JexNativeCommand') {
                [pscustomobject]@{
                    Source   = $Source
                    Mutation = 'Unresolved command target is not allowed in validation tools'
                    Command  = $command.Extent.Text
                }
            }
            continue
        }

        $normalizedName = [IO.Path]::GetFileNameWithoutExtension($commandName).ToLowerInvariant()
        $extent = $command.Extent.Text
        if ($normalizedName -eq 'invoke-jexnativecommand') {
            $targetParameter = 'FilePath'
            $targetAst = Get-JexNamedArgumentAst -Command $command -ParameterName $targetParameter
            $target = Get-JexConstantString -Node $targetAst
            $cloudTargets = @('a365', 'a365.exe', 'az', 'az.cmd', 'atk', 'atk.ps1', 'atk.cmd')
            if ([string]::IsNullOrWhiteSpace($target)) {
                if ((Get-JexContainingFunctionName -Node $command) -ne 'Invoke-JexNativeCommand') {
                    [pscustomobject]@{
                        Source   = $Source
                        Mutation = 'Dynamic cloud CLI target is not allowed'
                        Command  = $extent
                    }
                }
                continue
            }
            $targetFileName = [IO.Path]::GetFileName($target).ToLowerInvariant()
            if ($targetFileName -notin $cloudTargets) {
                continue
            }
            $normalizedName = [IO.Path]::GetFileNameWithoutExtension($targetFileName).ToLowerInvariant()
            $argumentAst = Get-JexNamedArgumentAst -Command $command -ParameterName 'ArgumentList'
            if ($null -eq $argumentAst) {
                [pscustomobject]@{ Source = $Source; Mutation = 'Dynamic cloud CLI arguments'; Command = $extent }
                continue
            }
            $literalArguments = @(Get-JexLiteralArgumentStrings -Node $argumentAst)
        }
        else {
            $literalArguments = @($command.CommandElements | Select-Object -Skip 1 | ForEach-Object {
                if ($_ -is [Management.Automation.Language.StringConstantExpressionAst]) {
                    $_.Value
                }
            } | Where-Object { $null -ne $_ })
        }

        $argumentText = ($literalArguments -join ' ').Trim().ToLowerInvariant()
        $allowed = switch ($normalizedName) {
            'a365' { $false; break }
            'az' {
                $argumentText -match '^version(?:\s|$)' -or
                $argumentText -match '^account\s+show(?:\s|$)' -or
                $argumentText -match '^resource\s+show(?:\s|$)'
                break
            }
            'atk' { $false; break }
            'new-featureconfiguration' { $false; break }
            'set-featureconfiguration' { $false; break }
            'remove-featureconfiguration' { $false; break }
            default {
                if ($normalizedName -match '^(?:new|set|remove)-az' -or
                    $normalizedName -match '^(?:new|update|remove)-mg') {
                    $false
                }
                else {
                    $true
                }
            }
        }

        if (-not $allowed) {
            $mutation = if ($normalizedName -in @('a365', 'atk')) {
                "Agent 365 and Agents Toolkit CLI commands are not allowed in backend validation tools: $normalizedName"
            }
            else {
                "Cloud command is not on the read-only allowlist: $normalizedName"
            }
            [pscustomobject]@{
                Source   = $Source
                Mutation = $mutation
                Command  = $extent
            }
        }

        if ($normalizedName -in @('invoke-restmethod', 'invoke-webrequest') -and
            $extent -match '(?i)-Method\s+(?:Post|Put|Patch|Delete)' -and
            $extent -notmatch '(?i)dataSecurityAndGovernance/processContent') {
            [pscustomobject]@{
                Source   = $Source
                Mutation = 'Non-read-only HTTP request is not an approved Purview probe'
                Command  = $extent
            }
        }
    }
}

function Get-JexMilestoneState {
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $manifestPath = Join-Path $root 'docs\milestones\milestones.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Milestone manifest is missing: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 20
    $manifestProperties = @($manifest.PSObject.Properties.Name)
    foreach ($requiredProperty in @('protocolVersion', 'currentMilestone', 'milestones')) {
        if ($requiredProperty -notin $manifestProperties) {
            throw "Milestone manifest is missing required property '$requiredProperty'."
        }
    }
    if ($manifest.protocolVersion -lt 1) {
        throw 'Milestone protocolVersion must be at least 1.'
    }

    $milestones = @($manifest.milestones)
    if ($milestones.Count -eq 0) {
        throw 'Milestone manifest must contain at least one milestone.'
    }
    $duplicateIds = @($milestones | Group-Object id | Where-Object Count -gt 1)
    if ($duplicateIds.Count -gt 0) {
        throw "Milestone IDs must be unique: $($duplicateIds.Name -join ', ')."
    }
    foreach ($milestone in $milestones) {
        $properties = @($milestone.PSObject.Properties.Name)
        foreach ($requiredProperty in @('id', 'name', 'status', 'allowsTenantReads', 'allowsTenantMutations', 'scope')) {
            if ($requiredProperty -notin $properties) {
                throw "Milestone '$($milestone.id)' is missing required property '$requiredProperty'."
            }
        }
        if ($milestone.id -notmatch '^M\d+$') {
            throw "Milestone ID '$($milestone.id)' is invalid."
        }
        if ($milestone.status -notin @('planned', 'active', 'complete', 'blocked')) {
            throw "Milestone '$($milestone.id)' has invalid status '$($milestone.status)'."
        }
        if ($milestone.allowsTenantReads -isnot [bool] -or $milestone.allowsTenantMutations -isnot [bool]) {
            throw "Milestone '$($milestone.id)' capability flags must be Boolean."
        }
        if ($properties -contains 'requiresExplicitUserActivation' -and
            $milestone.requiresExplicitUserActivation -and
            ($properties -notcontains 'activationPhrase' -or [string]::IsNullOrWhiteSpace($milestone.activationPhrase))) {
            throw "Milestone '$($milestone.id)' requires a non-empty activationPhrase."
        }
    }

    $current = @($milestones | Where-Object { $_.id -eq $manifest.currentMilestone })
    if ($current.Count -ne 1) {
        throw "Milestone manifest must contain exactly one current milestone named '$($manifest.currentMilestone)'."
    }
    if ($current[0].status -ne 'active') {
        throw "Current milestone '$($current[0].id)' must have status 'active'."
    }
    $activeMilestones = @($milestones | Where-Object status -eq 'active')
    if ($activeMilestones.Count -ne 1) {
        throw 'Milestone manifest must contain exactly one active milestone.'
    }

    [pscustomobject]@{
        Manifest = $manifest
        Current  = $current[0]
        Path     = $manifestPath
    }
}

function Get-JexPackageVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $PackageName,

        [string] $RepositoryRoot = $script:DefaultRepositoryRoot
    )

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $packageFile = Join-Path $root 'Directory.Packages.props'
    if (-not (Test-Path -LiteralPath $packageFile -PathType Leaf)) {
        return $null
    }

    [xml]$document = Get-Content -LiteralPath $packageFile -Raw
    $package = @($document.Project.ItemGroup.PackageVersion) |
        Where-Object { $_.Include -eq $PackageName } |
        Select-Object -First 1
    if ($null -eq $package) {
        return $null
    }

    [string]$package.Version
}

function Get-JexFirstPartyFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [string[]] $Extension = @(),

        [string[]] $Name = @()
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return @()
    }

    @(Get-ChildItem -LiteralPath $Path -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/](?:bin|obj|build|node_modules|\.git)[\\/]' -and
        ($Extension.Count -eq 0 -or $_.Extension -in $Extension) -and
        ($Name.Count -eq 0 -or $_.Name -in $Name)
    })
}

function Get-JexSourceLayout {
    <#
        .SYNOPSIS
        Resolves product-named backend source paths without depending on the product prefix.

        .DESCRIPTION
        Project, solution, and host file names carry the product name, so they change during a
        product rename. Validation discovers them structurally and reports unresolved paths instead
        of throwing, so a rename in progress produces a readable failure rather than a crash.
    #>
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $unresolved = [System.Collections.Generic.List[string]]::new()

    function Select-JexSinglePath {
        param(
            [Parameter(Mandatory)][string] $Description,
            [AllowEmptyCollection()][object[]] $Candidate
        )

        $resolved = @($Candidate | Where-Object {
            $null -ne $_ -and $_.FullName -notmatch '[\\/](?:bin|obj|build|node_modules|\.git)[\\/]'
        })
        if ($resolved.Count -eq 1) {
            return $resolved[0].FullName
        }
        $unresolved.Add("$Description (matches: $($resolved.Count))")
        ''
    }

    function Join-JexOptionalPath {
        param([AllowEmptyString()][string] $Directory, [string] $Leaf)

        if ([string]::IsNullOrWhiteSpace($Directory)) { return '' }
        Join-Path $Directory $Leaf
    }

    $solutionPath = Select-JexSinglePath -Description 'solution (*.slnx)' -Candidate @(
        Get-ChildItem -LiteralPath $root -File -Filter '*.slnx' -ErrorAction SilentlyContinue)
    $agentProjectPath = Select-JexSinglePath -Description 'agent project (server/agent/*/*.csproj)' -Candidate @(
        Get-JexFirstPartyFiles -Path (Join-Path $root 'server\agent') -Extension @('.csproj'))
    $hostProjectPath = Select-JexSinglePath -Description 'agent host project (server/agent-host/*/*.csproj)' -Candidate @(
        Get-JexFirstPartyFiles -Path (Join-Path $root 'server\agent-host') -Extension @('.csproj'))
    $mcpHostingProjectPath = Select-JexSinglePath -Description 'MCP hosting project (server/mcp/shared/*/*.csproj)' -Candidate @(
        Get-JexFirstPartyFiles -Path (Join-Path $root 'server\mcp\shared') -Extension @('.csproj'))

    $hostDirectory = if ($hostProjectPath) { Split-Path -Parent $hostProjectPath } else { '' }
    $mcpHostingDirectory = if ($mcpHostingProjectPath) { Split-Path -Parent $mcpHostingProjectPath } else { '' }

    $applicationPath = if ($hostDirectory) {
        Select-JexSinglePath -Description 'host application class (*Application.cs)' -Candidate @(
            Get-ChildItem -LiteralPath $hostDirectory -File -Filter '*Application.cs' -ErrorAction SilentlyContinue)
    }
    else { '' }

    $hostTestsProjectPath = Select-JexSinglePath -Description 'agent host tests project (tests/*.AgentHost.Tests)' -Candidate @(
        Get-JexFirstPartyFiles -Path (Join-Path $root 'tests') -Extension @('.csproj') |
            Where-Object { $_.Name -like '*.AgentHost.Tests.csproj' })
    $mcpHostingTestsProjectPath = Select-JexSinglePath -Description 'MCP hosting tests project (tests/*.Mcp.Hosting.Tests)' -Candidate @(
        Get-JexFirstPartyFiles -Path (Join-Path $root 'tests') -Extension @('.csproj') |
            Where-Object { $_.Name -like '*.Mcp.Hosting.Tests.csproj' })
    $hostTestsDirectory = if ($hostTestsProjectPath) { Split-Path -Parent $hostTestsProjectPath } else { '' }
    $mcpHostingTestsDirectory = if ($mcpHostingTestsProjectPath) { Split-Path -Parent $mcpHostingTestsProjectPath } else { '' }

    $mcpServiceProjects = [ordered]@{}
    foreach ($service in @('attractions', 'weather', 'accommodation', 'currency')) {
        $mcpServiceProjects[$service] = Select-JexSinglePath `
            -Description "MCP $service project (server/mcp/$service/*/*.csproj)" `
            -Candidate @(Get-JexFirstPartyFiles -Path (Join-Path $root "server\mcp\$service") -Extension @('.csproj'))
    }

    [pscustomobject][ordered]@{
        Root                            = $root
        SolutionPath                    = $solutionPath
        AgentProjectPath                = $agentProjectPath
        HostDirectory                   = $hostDirectory
        HostProjectPath                 = $hostProjectPath
        ProgramPath                     = Join-JexOptionalPath -Directory $hostDirectory -Leaf 'Program.cs'
        ApplicationPath                 = $applicationPath
        HostSettingsPath                = Join-JexOptionalPath -Directory $hostDirectory -Leaf 'appsettings.json'
        OboExchangePath                 = Join-JexOptionalPath -Directory $hostDirectory -Leaf 'AgentIdentityOboTokenExchange.cs'
        FrontendIdentityBindingPath     = Join-JexOptionalPath -Directory $hostDirectory -Leaf 'AgentFrontendIdentityBinding.cs'
        InternalMcpOptionsPath          = Join-JexOptionalPath -Directory $hostDirectory -Leaf 'InternalMcpOptions.cs'
        InternalMcpCatalogPath          = Join-JexOptionalPath -Directory $hostDirectory -Leaf 'InternalMcpToolCatalog.cs'
        McpAuthorizationPath            = Join-JexOptionalPath -Directory $mcpHostingDirectory -Leaf 'McpWorkloadAuthorization.cs'
        HostTestsDirectory              = $hostTestsDirectory
        HostTestsProjectPath            = $hostTestsProjectPath
        AuthorizationTestsPath          = Join-JexOptionalPath -Directory $hostTestsDirectory -Leaf 'AgentIdentityAuthorizationOptionsTests.cs'
        OboExchangeTestsPath            = Join-JexOptionalPath -Directory $hostTestsDirectory -Leaf 'AgentIdentityOboTokenExchangeTests.cs'
        FrontendIdentityBindingTestsPath = Join-JexOptionalPath -Directory $hostTestsDirectory -Leaf 'AgentFrontendIdentityBindingTests.cs'
        ObservabilityTokenCacheTestsPath = Join-JexOptionalPath -Directory $hostTestsDirectory -Leaf 'ObservabilityTokenCacheTests.cs'
        InternalMcpCatalogTestsPath     = Join-JexOptionalPath -Directory $hostTestsDirectory -Leaf 'InternalMcpToolCatalogTests.cs'
        McpAuthorizationTestsPath       = Join-JexOptionalPath -Directory $mcpHostingTestsDirectory -Leaf 'McpWorkloadAuthorizationTests.cs'
        McpServiceProjects              = $mcpServiceProjects
        UnresolvedPaths                 = @($unresolved)
    }
}

function Test-JexPrerequisites {
    [CmdletBinding()]
    param(
        [string] $RepositoryRoot = $script:DefaultRepositoryRoot,

        [switch] $SkipCloudCliVersionCommands
    )

    $requirements = @(
        @{ Name = '.NET SDK'; Command = 'dotnet'; Arguments = @('--version'); Minimum = [version]'10.0' },
        @{ Name = 'PowerShell'; Command = 'pwsh'; Arguments = @('--version'); Minimum = [version]'7.0' },
        @{ Name = 'Azure CLI'; Command = 'az'; Arguments = @('version', '--output', 'json'); Minimum = [version]'2.0' },
        @{ Name = 'Git'; Command = 'git'; Arguments = @('--version'); Minimum = [version]'2.0' }
    )

    $results = foreach ($requirement in $requirements) {
        $command = Get-Command $requirement.Command -ErrorAction SilentlyContinue
        $resolvedCli = if ($null -ne $command) {
            [pscustomobject]@{
                FilePath = $command.Source
                Source   = 'PATH'
            }
        }
        if ($null -eq $resolvedCli) {
            New-JexValidationResult -Area 'Prerequisites' -Check $requirement.Name -Status 'Fail' `
                -Message "$($requirement.Command) is not installed or is not on PATH." `
                -Remediation "Restore or install $($requirement.Name) and run this check again."
            continue
        }

        if ($SkipCloudCliVersionCommands -and $requirement.Command -eq 'az') {
            New-JexValidationResult -Area 'Prerequisites' -Check $requirement.Name -Status 'Skip' `
                -Message "$($requirement.Command) is available, but its version command was not executed in offline aggregate validation." `
                -Data @{
                    Command         = $resolvedCli.FilePath
                    Source          = $resolvedCli.Source
                    CommandExecuted = $false
                }
            continue
        }

        $workingDirectory = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
        $invocation = switch ($requirement.Command) {
            'dotnet' { Invoke-JexNativeCommand -FilePath 'dotnet' -ArgumentList @('--version') -WorkingDirectory $workingDirectory; break }
            'pwsh' { Invoke-JexNativeCommand -FilePath 'pwsh' -ArgumentList @('--version') -WorkingDirectory $workingDirectory; break }
            'az' { Invoke-JexNativeCommand -FilePath 'az' -ArgumentList @('version', '--output', 'json') -WorkingDirectory $workingDirectory; break }
            'git' { Invoke-JexNativeCommand -FilePath 'git' -ArgumentList @('--version') -WorkingDirectory $workingDirectory; break }
            default { [pscustomobject]@{ ExitCode = -1; Output = "Unsupported prerequisite command: $($requirement.Command)" } }
        }
        if ($invocation.ExitCode -ne 0) {
            New-JexValidationResult -Area 'Prerequisites' -Check $requirement.Name -Status 'Fail' `
                -Message "$($requirement.Command) returned exit code $($invocation.ExitCode)." `
                -Remediation $invocation.Output
            continue
        }

        $version = ConvertTo-JexVersion -Value $invocation.Output
        if ($null -eq $version) {
            New-JexValidationResult -Area 'Prerequisites' -Check $requirement.Name -Status 'Warn' `
                -Message "$($requirement.Command) is available, but its version could not be parsed." `
                -Data @{ Output = $invocation.Output }
            continue
        }

        if ($version -lt $requirement.Minimum) {
            New-JexValidationResult -Area 'Prerequisites' -Check $requirement.Name -Status 'Fail' `
                -Message "Version $version is below the required $($requirement.Minimum)." `
                -Remediation "Upgrade $($requirement.Name)." `
                -Data @{ Version = $version.ToString(); Minimum = $requirement.Minimum.ToString() }
            continue
        }

        New-JexValidationResult -Area 'Prerequisites' -Check $requirement.Name -Status 'Pass' `
            -Message "Version $version is available." `
            -Data @{ Version = $version.ToString(); Command = $resolvedCli.FilePath; Source = $resolvedCli.Source }
    }

    @($results)
}

function Find-JexPotentialSecrets {
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $candidateFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {
        $_.FullName -notmatch '[\\/](?:bin|obj|build|node_modules|\.git|\.azure|\.copilot-azure|\.a365|teams)[\\/]' -and
        $_.Name -notin @('a365.generated.config.json', 'ToolingManifest.json') -and
        ($_.Name -eq '.env' -or $_.Name -like '.env.*' -or
            $_.Extension -in @('.json', '.yml', '.yaml', '.config', '.xml'))
    })
    $findings = [System.Collections.Generic.List[string]]::new()
    $assignmentPattern = [regex]'(?im)^\s*["'']?(?<key>[a-z0-9_.-]+)["'']?\s*[:=]\s*["'']?(?<value>[^\r\n"'']*)'

    function Test-JexSecretValue {
        param([AllowNull()][object] $Value)

        if ($null -eq $Value -or $Value -isnot [string]) {
            return $false
        }
        $text = $Value.Trim()
        $text -and $text -notmatch '^(?:<.*>|\$\{\{.*\}\}|\$\(.*\)|\$\{.*\}|null|false|true)$'
    }

    function Find-JexJsonSecretProperty {
        param(
            [Text.Json.JsonElement] $Node,
            [string] $PropertyPath = '$'
        )

        switch ($Node.ValueKind) {
            ([Text.Json.JsonValueKind]::Object) {
                foreach ($property in $Node.EnumerateObject()) {
                    $normalizedName = $property.Name -replace '[-_]', ''
                    $childPath = "$PropertyPath.$($property.Name)"
                    if ($normalizedName -match '(?:clientsecret|apikey|accesstoken|bearertoken|password|connectionstring)$' -and
                        $property.Value.ValueKind -eq [Text.Json.JsonValueKind]::String -and
                        (Test-JexSecretValue -Value $property.Value.GetString())) {
                        $childPath
                    }
                    Find-JexJsonSecretProperty -Node $property.Value -PropertyPath $childPath
                }
                break
            }
            ([Text.Json.JsonValueKind]::Array) {
                $index = 0
                foreach ($item in $Node.EnumerateArray()) {
                    Find-JexJsonSecretProperty -Node $item -PropertyPath "$PropertyPath[$index]"
                    $index++
                }
                break
            }
        }
    }

    foreach ($file in $candidateFiles) {
        [string]$content = Get-Content -LiteralPath $file.FullName -Raw
        if ($null -eq $content) {
            $content = ''
        }
        $relativePath = [System.IO.Path]::GetRelativePath($root, $file.FullName)
        if ($file.Extension -eq '.json' -and $file.Name -notin @('package-lock.json', 'npm-shrinkwrap.json')) {
            $jsonDocument = $null
            try {
                $jsonDocument = [Text.Json.JsonDocument]::Parse($content)
                foreach ($propertyPath in @(Find-JexJsonSecretProperty -Node $jsonDocument.RootElement)) {
                    $findings.Add("$relativePath ($propertyPath)")
                }
            }
            catch {
                $findings.Add("$relativePath (invalid JSON; secret scan incomplete)")
            }
            finally {
                if ($null -ne $jsonDocument) {
                    $jsonDocument.Dispose()
                }
            }
        }
        if ($file.Extension -ne '.json') {
            foreach ($match in $assignmentPattern.Matches($content)) {
                $normalizedKey = $match.Groups['key'].Value -replace '[-_.]', ''
                if ($normalizedKey -notmatch '(?:clientsecret|apikey|accesstoken|bearertoken|password|connectionstring)$') {
                    continue
                }
                $value = $match.Groups['value'].Value.Trim()
                if (Test-JexSecretValue -Value $value) {
                    $findings.Add($relativePath)
                }
            }
        }

        if ($content -match '(?i)Bearer\s+eyJ[A-Za-z0-9_-]+\.') {
            $findings.Add($relativePath)
        }
    }

    @($findings | Sort-Object -Unique)
}

function Find-JexCommittedIdentifier {
    <#
        .SYNOPSIS
        Finds tenant-bound identifiers that must never be committed to source.

        .DESCRIPTION
        Fixed non-secret deployment names may be committed: the target resource group, the existing
        Foundry account and project, its endpoint, and the model deployment name. Subscription GUIDs,
        tenant or directory IDs, principal and object IDs, owner user principal names, and full ARM
        resource IDs are runtime values and must stay command parameters or placeholders.

        Findings report the file, rule, and line only. The matched value is never returned, so the
        result object and JSON output stay safe to print and store.
    #>
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $guid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    $allowedMailDomains = @(
        'example.com', 'example.org', 'example.net', 'example',
        'contoso.com', 'contoso.example', 'fabrikam.example',
        'localhost', 'invalid', 'test'
    )
    $rules = @(
        @{ Rule = 'Full ARM resource ID'; Pattern = "/subscriptions/(?<guid>$guid)" },
        @{ Rule = 'Subscription ID'; Pattern = "(?i)\bsubscription[^\r\n]{0,16}?(?<guid>$guid)" },
        @{ Rule = 'Tenant or directory ID'; Pattern = "(?i)\b(tenant|directory)[^\r\n]{0,16}?(?<guid>$guid)" },
        @{ Rule = 'Principal or object ID'; Pattern = "(?i)\b(principal|object|assignee)[-_ ]?id\b[^\r\n]{0,16}?(?<guid>$guid)" }
    )
    $mailPattern = '(?<local>[A-Za-z0-9._%+-]+)@(?<domain>[A-Za-z0-9.-]+\.[A-Za-z]{2,})'

    function Test-JexSyntheticGuidValue {
        param([string] $Value)

        $hex = $Value.Replace('-', '')
        if ($hex.Length -ne 32) {
            return $false
        }
        $dominant = ($hex.ToCharArray() | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Count
        # Documentation and unit-test placeholders repeat one digit and differ only in the RFC 4122
        # version and variant nibbles. A real identifier never repeats a character this heavily.
        $dominant -ge 28
    }

    $candidateFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {
        $_.FullName -notmatch '[\\/](?:bin|obj|build|node_modules|\.git|\.vs|\.azure|\.copilot-azure|\.a365|\.config)[\\/]' -and
        ($_.Extension -in @('.bicep', '.bicepparam', '.json', '.md', '.ps1', '.psm1', '.cs', '.csproj',
            '.props', '.slnx', '.yml', '.yaml', '.config', '.xml', '.env') -or
            $_.Name -like 'Dockerfile*')
    })

    foreach ($file in $candidateFiles) {
        $relativePath = [IO.Path]::GetRelativePath($root, $file.FullName)
        $lineNumber = 0
        foreach ($line in @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
            $lineNumber++
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            foreach ($rule in $rules) {
                foreach ($match in [regex]::Matches($line, $rule.Pattern)) {
                    if (Test-JexSyntheticGuidValue -Value $match.Groups['guid'].Value) {
                        continue
                    }
                    [pscustomobject]@{ Path = $relativePath; Rule = $rule.Rule; Line = $lineNumber }
                }
            }
            foreach ($match in [regex]::Matches($line, $mailPattern)) {
                $domain = $match.Groups['domain'].Value.ToLowerInvariant()
                if ($domain -notin $allowedMailDomains) {
                    [pscustomobject]@{ Path = $relativePath; Rule = 'User principal name or mailbox'; Line = $lineNumber }
                }
            }
        }
    }
}

function Find-JexSyntheticSensitiveData {
    <#
        .SYNOPSIS
        Finds sensitive-data test literals that are outside the reserved synthetic ranges.

        .DESCRIPTION
        Purview acceptance uses exactly three reserved synthetic cases: a Japan passport number, a
        Japanese residence card number, and the industry-reserved test card number. The first two use
        reserved prefixes that can never belong to a real document. Exact test values belong to the
        Direct Line frontend and must not be duplicated into this backend. Findings report file, rule,
        and line only; no matched value is returned.
    #>
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $reservedPrefix = 'ZZ'

    function Test-JexLuhnChecksum {
        param([string] $Digits)

        $sum = 0
        $alternate = $false
        for ($index = $Digits.Length - 1; $index -ge 0; $index--) {
            $digit = [int][string]$Digits[$index]
            if ($alternate) {
                $digit *= 2
                if ($digit -gt 9) { $digit -= 9 }
            }
            $sum += $digit
            $alternate = -not $alternate
        }
        ($sum % 10) -eq 0
    }

    $candidateFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {
        $_.FullName -notmatch '[\\/](?:bin|obj|build|node_modules|\.git|\.vs|\.azure|\.copilot-azure|\.a365|\.config)[\\/]' -and
        $_.Extension -in @('.cs', '.json', '.md', '.ps1', '.psm1', '.bicep', '.bicepparam', '.csproj',
            '.slnx', '.props', '.yml', '.yaml', '.xml', '.config', '.env')
    })

    foreach ($file in $candidateFiles) {
        $relativePath = [IO.Path]::GetRelativePath($root, $file.FullName)
        $lineNumber = 0
        foreach ($line in @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
            $lineNumber++
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            # Bicep records a numeric template hash that can incidentally satisfy the checksum.
            if ($line -notmatch '(?i)templateHash') {
                foreach ($match in [regex]::Matches($line, '(?<![0-9])[0-9]{13,19}(?![0-9])')) {
                    if (Test-JexLuhnChecksum -Digits $match.Value) {
                        [pscustomobject]@{ Path = $relativePath; Rule = 'Card-shaped checksum-valid number'; Line = $lineNumber }
                    }
                }
            }

            foreach ($match in [regex]::Matches($line, '(?<![A-Za-z0-9])(?<value>[A-Z]{2}[0-9]{7})(?![0-9])')) {
                if (-not $match.Groups['value'].Value.StartsWith($reservedPrefix, [StringComparison]::Ordinal)) {
                    [pscustomobject]@{ Path = $relativePath; Rule = 'Passport-shaped literal outside the reserved range'; Line = $lineNumber }
                }
            }

            foreach ($match in [regex]::Matches($line, '(?<![A-Za-z0-9])(?<value>[A-Z]{2}[0-9]{8}[A-Z]{2})(?![A-Za-z0-9])')) {
                if (-not $match.Groups['value'].Value.StartsWith($reservedPrefix, [StringComparison]::Ordinal)) {
                    [pscustomobject]@{ Path = $relativePath; Rule = 'Residence-card-shaped literal outside the reserved range'; Line = $lineNumber }
                }
            }
        }
    }
}

function Get-JexSyntheticCasePolicy {
    <#
        .SYNOPSIS
        Returns the synthetic Purview acceptance cases and confirms the active milestone declares them.
    #>
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $expectedCases = @('Japan passport', 'Japanese residence card', 'reserved test card')
    $retiredCases = @('Korean passport', 'Korean resident-registration')

    $milestoneId = ''
    $declaredText = ''
    try {
        $milestone = Get-JexMilestoneState -RepositoryRoot $root
        $milestoneId = $milestone.Current.id
        $properties = @($milestone.Current.PSObject.Properties.Name)
        foreach ($section in @('scope', 'acceptanceEvidence')) {
            if ($section -in $properties) {
                $declaredText += (@($milestone.Current.$section) -join "`n") + "`n"
            }
        }
    }
    catch {
        $declaredText = ''
    }

    $missingCases = @($expectedCases | Where-Object {
        -not $declaredText.Contains($_, [StringComparison]::OrdinalIgnoreCase)
    })
    $retiredDeclared = @($retiredCases | Where-Object {
        $declaredText.Contains($_, [StringComparison]::OrdinalIgnoreCase)
    })

    [pscustomobject][ordered]@{
        MilestoneId     = $milestoneId
        ExpectedCases   = @($expectedCases)
        MissingCases    = @($missingCases)
        RetiredDeclared = @($retiredDeclared)
        IsConsistent    = $missingCases.Count -eq 0 -and $retiredDeclared.Count -eq 0
    }
}

function Test-JexRepositoryConfiguration {
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $layout = Get-JexSourceLayout -RepositoryRoot $root
    $requiredPaths = @(
        'Directory.Packages.props',
        'contracts\frontend-backend-contract.json',
        'contracts\frontend-backend-contract.schema.json',
        'docs\milestones\milestones.json'
    )
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($relativePath in $requiredPaths) {
        $exists = Test-Path -LiteralPath (Join-Path $root $relativePath)
        $results.Add((New-JexValidationResult -Area 'Repository' -Check "Path: $relativePath" `
            -Status $(if ($exists) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($exists) { 'Required path exists.' } else { 'Required path is missing.' }) `
            -Remediation $(if ($exists) { '' } else { "Restore $relativePath." })))
    }

    $layoutResolved = @($layout.UnresolvedPaths).Count -eq 0
    $results.Add((New-JexValidationResult -Area 'Repository' -Check 'Source layout discovery' `
        -Status $(if ($layoutResolved) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($layoutResolved) { 'Solution, host, MCP, and test projects each resolve to exactly one path.' } else { 'One or more product-named source paths did not resolve to exactly one path.' }) `
        -Remediation $(if ($layoutResolved) { '' } else { 'Finish the in-flight project rename and remove duplicate or leftover project directories.' }) `
        -Data @{ UnresolvedPaths = @($layout.UnresolvedPaths) }))
    if (-not $layoutResolved) {
        return @($results)
    }

    try {
        $milestone = Get-JexMilestoneState -RepositoryRoot $root
        $validState = $milestone.Current.status -eq 'active'
        $results.Add((New-JexValidationResult -Area 'Repository' -Check 'Milestone state' `
            -Status $(if ($validState) { 'Pass' } else { 'Fail' }) `
            -Message "Current milestone is $($milestone.Current.id) with status '$($milestone.Current.status)'." `
            -Remediation $(if ($validState) { '' } else { 'Set exactly one current milestone to active through a reviewed protocol transition.' })))
    }
    catch {
        $results.Add((New-JexValidationResult -Area 'Repository' -Check 'Milestone state' -Status 'Fail' `
            -Message $_.Exception.Message -Remediation 'Repair docs/milestones/milestones.json.'))
        $milestone = $null
    }

    $agentFrameworkVersion = Get-JexPackageVersion -PackageName 'Microsoft.Agents.AI' -RepositoryRoot $root
    $a365RuntimeVersion = Get-JexPackageVersion -PackageName 'Microsoft.Agents.A365.Runtime' -RepositoryRoot $root
    $mcpClientVersion = Get-JexPackageVersion -PackageName 'ModelContextProtocol' -RepositoryRoot $root
    foreach ($package in @(
        @{ Name = 'Microsoft Agent Framework'; Version = $agentFrameworkVersion },
        @{ Name = 'Agent 365 runtime'; Version = $a365RuntimeVersion },
        @{ Name = 'Official MCP client'; Version = $mcpClientVersion }
    )) {
        $present = -not [string]::IsNullOrWhiteSpace($package.Version)
        $results.Add((New-JexValidationResult -Area 'Repository' -Check $package.Name `
            -Status $(if ($present) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($present) { "Package is centrally pinned to $($package.Version)." } else { 'Required package pin is missing.' }) `
            -Remediation $(if ($present) { '' } else { 'Add the package to Directory.Packages.props.' })))
    }

    $programPath = $layout.ProgramPath
    $applicationPath = $layout.ApplicationPath
    $agentProjectPath = $layout.AgentProjectPath
    $hostProjectPath = $layout.HostProjectPath
    $hostSettingsPath = $layout.HostSettingsPath
    $oboExchangePath = $layout.OboExchangePath
    $frontendIdentityBindingPath = $layout.FrontendIdentityBindingPath
    $internalMcpOptionsPath = $layout.InternalMcpOptionsPath
    $internalMcpCatalogPath = $layout.InternalMcpCatalogPath
    $authorizationTestsPath = $layout.AuthorizationTestsPath
    $oboExchangeTestsPath = $layout.OboExchangeTestsPath
    $frontendIdentityBindingTestsPath = $layout.FrontendIdentityBindingTestsPath
    $observabilityTokenCacheTestsPath = $layout.ObservabilityTokenCacheTestsPath
    $internalMcpCatalogTestsPath = $layout.InternalMcpCatalogTestsPath
    $mcpAuthorizationPath = $layout.McpAuthorizationPath
    $mcpAuthorizationTestsPath = $layout.McpAuthorizationTestsPath
    $missingSourceFiles = @(@(
        $programPath, $applicationPath, $agentProjectPath, $hostProjectPath, $hostSettingsPath,
        $oboExchangePath, $frontendIdentityBindingPath, $internalMcpOptionsPath, $internalMcpCatalogPath,
        $authorizationTestsPath, $oboExchangeTestsPath, $frontendIdentityBindingTestsPath,
        $observabilityTokenCacheTestsPath, $internalMcpCatalogTestsPath, $mcpAuthorizationPath,
        $mcpAuthorizationTestsPath
    ) | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) } |
        ForEach-Object { [IO.Path]::GetRelativePath($root, $_) })
    if ($missingSourceFiles.Count -gt 0) {
        $results.Add((New-JexValidationResult -Area 'Repository' -Check 'Host boundary source files' -Status 'Fail' `
            -Message 'One or more required host, MCP, or test source files are missing.' `
            -Remediation 'Restore the missing files or finish the in-flight rename before running validation.' `
            -Data @{ MissingFiles = @($missingSourceFiles) }))
        return @($results)
    }

    $mainBicepPath = Join-Path $root 'infra\main.bicep'
    $hostBicepPath = Join-Path $root 'infra\modules\agent-host-container-app.bicep'
    $mcpApiApplicationBicepPath = Join-Path $root 'infra\modules\mcp-api-application.bicep'
    $mcpContainerModulePaths = @(
        'infra\modules\attractions-mcp-container-app.bicep',
        'infra\modules\weather-mcp-container-app.bicep',
        'infra\modules\accommodation-mcp-container-app.bicep',
        'infra\modules\currency-mcp-container-app.bicep'
    )
    $programContent = Get-Content -LiteralPath $programPath -Raw
    $applicationContent = Get-Content -LiteralPath $applicationPath -Raw
    $agentProjectContent = Get-Content -LiteralPath $agentProjectPath -Raw
    $hostProjectContent = Get-Content -LiteralPath $hostProjectPath -Raw
    $hostSettingsContent = Get-Content -LiteralPath $hostSettingsPath -Raw
    $oboExchangeContent = Get-Content -LiteralPath $oboExchangePath -Raw
    $frontendIdentityBindingContent = Get-Content -LiteralPath $frontendIdentityBindingPath -Raw
    $internalMcpOptionsContent = Get-Content -LiteralPath $internalMcpOptionsPath -Raw
    $internalMcpCatalogContent = Get-Content -LiteralPath $internalMcpCatalogPath -Raw
    $authorizationTestsContent = Get-Content -LiteralPath $authorizationTestsPath -Raw
    $oboExchangeTestsContent = Get-Content -LiteralPath $oboExchangeTestsPath -Raw
    $frontendIdentityBindingTestsContent = Get-Content -LiteralPath $frontendIdentityBindingTestsPath -Raw
    $observabilityTokenCacheTestsContent = Get-Content -LiteralPath $observabilityTokenCacheTestsPath -Raw
    $internalMcpCatalogTestsContent = Get-Content -LiteralPath $internalMcpCatalogTestsPath -Raw
    $mcpAuthorizationContent = Get-Content -LiteralPath $mcpAuthorizationPath -Raw
    $mcpAuthorizationTestsContent = Get-Content -LiteralPath $mcpAuthorizationTestsPath -Raw
    $mainBicepContent = Get-Content -LiteralPath $mainBicepPath -Raw
    $hostBicepContent = Get-Content -LiteralPath $hostBicepPath -Raw
    $mcpApiApplicationBicepContent = Get-Content -LiteralPath $mcpApiApplicationBicepPath -Raw
    $mcpContainerModuleContents = @($mcpContainerModulePaths | ForEach-Object {
        Get-Content -LiteralPath (Join-Path $root $_) -Raw
    })
    $customMcpLoading = $programContent.Contains('InternalMcpToolCatalog', [StringComparison]::Ordinal) -and
        $applicationContent.Contains('_internalMcpTools.OpenAsync', [StringComparison]::Ordinal)
    $workIqCompatibilityGate = $programContent.Contains('options => !options.EnableWorkIq', [StringComparison]::Ordinal) -and
        $hostSettingsContent -match '"EnableWorkIq"\s*:\s*false'
    $runtimeDependencyPinning = (
        -not [string]::IsNullOrWhiteSpace(
            (Get-JexPackageVersion -PackageName 'Microsoft.AspNetCore.Authentication.JwtBearer' -RepositoryRoot $root)) -and
        -not [string]::IsNullOrWhiteSpace(
            (Get-JexPackageVersion -PackageName 'System.IdentityModel.Tokens.Jwt' -RepositoryRoot $root)) -and
        -not [string]::IsNullOrWhiteSpace(
            (Get-JexPackageVersion -PackageName 'Microsoft.IdentityModel.Protocols' -RepositoryRoot $root)) -and
        -not [string]::IsNullOrWhiteSpace(
            (Get-JexPackageVersion -PackageName 'Microsoft.IdentityModel.Protocols.OpenIdConnect' -RepositoryRoot $root)) -and
        -not [string]::IsNullOrWhiteSpace(
            (Get-JexPackageVersion -PackageName 'Microsoft.IdentityModel.Tokens' -RepositoryRoot $root)) -and
        -not [string]::IsNullOrWhiteSpace(
            (Get-JexPackageVersion -PackageName 'Microsoft.IdentityModel.Validators' -RepositoryRoot $root)) -and
        -not [string]::IsNullOrWhiteSpace(
            (Get-JexPackageVersion -PackageName 'Microsoft.Extensions.AI' -RepositoryRoot $root)) -and
        $hostProjectContent.Contains(
            '<PackageReference Include="Microsoft.AspNetCore.Authentication.JwtBearer" />',
            [StringComparison]::Ordinal) -and
        $hostProjectContent.Contains(
            '<PackageReference Include="System.IdentityModel.Tokens.Jwt" />',
            [StringComparison]::Ordinal) -and
        $hostProjectContent.Contains(
            '<PackageReference Include="Microsoft.IdentityModel.Protocols" />',
            [StringComparison]::Ordinal) -and
        $hostProjectContent.Contains(
            '<PackageReference Include="Microsoft.IdentityModel.Protocols.OpenIdConnect" />',
            [StringComparison]::Ordinal) -and
        $hostProjectContent.Contains(
            '<PackageReference Include="Microsoft.IdentityModel.Tokens" />',
            [StringComparison]::Ordinal) -and
        $hostProjectContent.Contains(
            '<PackageReference Include="Microsoft.IdentityModel.Validators" />',
            [StringComparison]::Ordinal) -and
        $hostProjectContent.Contains(
            '<PackageReference Include="Microsoft.Extensions.AI" />',
            [StringComparison]::Ordinal) -and
        $agentProjectContent.Contains(
            '<PackageReference Include="Microsoft.Extensions.AI" />',
            [StringComparison]::Ordinal)
    )
    $dualFrontendRoutes = $programContent -match '(?s)MapAgentMessageEndpoint\s*\(\s*"/api/messages"\s*,\s*AgentFrontendMode\.AgenticUser\s*\)' -and
        $programContent -match '(?s)MapAgentMessageEndpoint\s*\(\s*"/api/messages/obo"\s*,\s*AgentFrontendMode\.OnBehalfOf\s*\)'
    $frontendChannelAudienceMapping = $mainBicepContent.Contains('param agent365AgentIds Agent365AgentIds', [StringComparison]::Ordinal) -and
        $mainBicepContent.Contains('agent365AgentIds: agent365AgentIds', [StringComparison]::Ordinal) -and
        $mainBicepContent.Contains('oboChannelAppId: oboChannelAppId', [StringComparison]::Ordinal) -and
        $hostBicepContent.Contains('param agent365AgentIds Agent365AgentIds', [StringComparison]::Ordinal) -and
        $hostBicepContent.Contains("name: 'TokenValidation__Audiences__AgenticUser'", [StringComparison]::Ordinal) -and
        $hostBicepContent -match "(?s)name:\s*'TokenValidation__Audiences__AgenticUser'\s*value:\s*agent365BlueprintId" -and
        $hostBicepContent.Contains("name: 'TokenValidation__Audiences__OnBehalfOf'", [StringComparison]::Ordinal) -and
        $hostBicepContent -match "(?s)name:\s*'TokenValidation__Audiences__OnBehalfOf'\s*value:\s*oboChannelAppId" -and
        $hostBicepContent -notmatch "Connections__ServiceConnection__Settings__AgentId" -and
        $hostBicepContent.Contains("name: 'ConnectionsMap__0__Audience'", [StringComparison]::Ordinal) -and
        $hostBicepContent.Contains("name: 'ConnectionsMap__1__Audience'", [StringComparison]::Ordinal) -and
        $hostBicepContent.Contains("value: 'OboChannelConnection'", [StringComparison]::Ordinal)

    $hostSourceDirectory = $layout.HostDirectory
    $configurationBoundaryFiles = @(
        Get-ChildItem -LiteralPath $hostSourceDirectory -File -Filter 'appsettings*.json'
        Get-ChildItem -LiteralPath (Join-Path $root 'infra') -Recurse -File -Filter '*.bicep'
    )
    $legacyGenericOboFindings = @(
        foreach ($file in $configurationBoundaryFiles) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            foreach ($match in [regex]::Matches(
                $content,
                '(?i)(?<![A-Za-z0-9])OBO(?:ConnectionName|Scopes)(?![A-Za-z0-9])')) {
                [pscustomobject]@{
                    Path    = [IO.Path]::GetRelativePath($root, $file.FullName)
                    Setting = $match.Value
                }
            }
        }
    )
    $oboAuthorizationShape = $false
    $oboConnectionShape = $false
    try {
        $hostSettings = $hostSettingsContent | ConvertFrom-Json -Depth 30 -ErrorAction Stop
        $handlers = $hostSettings.AgentApplication.UserAuthorization.Handlers
        $oboHandler = $handlers.'obo-user'
        $oboHandlerSettingNames = @($oboHandler.Settings.PSObject.Properties.Name)
        $azureBotHandlers = @($handlers.PSObject.Properties | Where-Object {
            $_.Value.Type -eq 'AzureBotUserAuthorization'
        })
        $oboAuthorizationHandlers = $hostSettings.AgentIdentityAuthorization.OnBehalfOf
        $oboAuthorizationHandlerNames = @(
            $oboAuthorizationHandlers.FoundryAuthHandlerName
            $oboAuthorizationHandlers.PurviewAuthHandlerName
            $oboAuthorizationHandlers.InternalMcpAuthHandlerName
        )
        $oboAuthorizationShape = $azureBotHandlers.Count -eq 1 -and
            $azureBotHandlers[0].Name -eq 'obo-user' -and
            $oboHandlerSettingNames.Count -eq 1 -and
            $oboHandlerSettingNames[0] -eq 'AzureBotOAuthConnectionName' -and
            -not [string]::IsNullOrWhiteSpace($oboHandler.Settings.AzureBotOAuthConnectionName) -and
            @($oboAuthorizationHandlerNames | Where-Object { $_ -eq 'obo-user' }).Count -eq 3

        $oboServiceSettings = $hostSettings.Connections.OboServiceConnection.Settings
        $oboServiceSettingNames = @($oboServiceSettings.PSObject.Properties.Name)
        $oboConnectionShape = $oboServiceSettings.AuthType -eq 'FederatedCredentials' -and
            $null -ne $oboServiceSettings.PSObject.Properties['ClientId'] -and
            $null -ne $oboServiceSettings.PSObject.Properties['FederatedClientId'] -and
            'AgentId' -notin $oboServiceSettingNames -and
            $null -ne $hostSettings.AgentIdentityObo.PSObject.Properties['AgentId'] -and
            $hostSettings.AgentIdentityObo.BlueprintConnectionName -eq 'OboServiceConnection'
    }
    catch {
        $oboAuthorizationShape = $false
        $oboConnectionShape = $false
    }
    $oboBicepHandlerSettingCount = [regex]::Matches(
        $hostBicepContent,
        'AgentApplication__UserAuthorization__Handlers__obo-user__').Count
    $oboBicepAuthorizationShape = $oboBicepHandlerSettingCount -eq 2 -and
        $hostBicepContent -match "(?s)\{\s*name:\s*'AgentApplication__UserAuthorization__Handlers__obo-user__Type'\s*value:\s*'AzureBotUserAuthorization'\s*\}" -and
        $hostBicepContent -match "(?s)\{\s*name:\s*'AgentApplication__UserAuthorization__Handlers__obo-user__Settings__AzureBotOAuthConnectionName'\s*value:\s*oboOAuthConnectionName\s*\}"
    $oboConfigurationBoundary = $legacyGenericOboFindings.Count -eq 0 -and
        $oboAuthorizationShape -and
        $oboBicepAuthorizationShape
    $oboConfigurationBoundary = $oboConfigurationBoundary -and
        $authorizationTestsContent.Contains('OboHandlerReturnsRawBlueprintUserAssertion', [StringComparison]::Ordinal) -and
        $authorizationTestsContent.Contains('ChildIdentityConnectionsUseBlueprintFederation', [StringComparison]::Ordinal)

    $twoStageChildExchange =
        $oboExchangeContent.Contains('connection is not IAgenticTokenProvider tokenProvider', [StringComparison]::Ordinal) -and
        $oboExchangeContent -match '(?s)GetAgenticApplicationTokenAsync\s*\(\s*tenantId\s*,\s*agentIdentityId\s*,\s*cancellationToken\s*\)' -and
        $oboExchangeContent -match '(?s)ConfidentialClientApplicationBuilder\s*\.Create\(agentIdentityId\)' -and
        $oboExchangeContent.Contains('.WithClientAssertion((AssertionRequestOptions _) => Task.FromResult(parentToken))', [StringComparison]::Ordinal) -and
        $oboExchangeContent -match '(?s)AcquireTokenOnBehalfOf\(scopes,\s*new UserAssertion\(userAssertion\)\)' -and
        $oboExchangeContent.Contains('scope.EndsWith("/.default", StringComparison.OrdinalIgnoreCase)', [StringComparison]::Ordinal) -and
        $oboExchangeContent.Contains('ResolveClientId(childToken)', [StringComparison]::Ordinal) -and
        $oboExchangeContent.Contains('claim.Type is "appid" or "azp"', [StringComparison]::Ordinal) -and
        $oboExchangeTestsContent.Contains('ExchangesParentTokenThenChildOboToken', [StringComparison]::Ordinal) -and
        $oboExchangeTestsContent.Contains('RejectsTokenStillMintedForBlueprint', [StringComparison]::Ordinal) -and
        $oboExchangeTestsContent.Contains('RejectsIndividualDelegatedScope', [StringComparison]::Ordinal) -and
        $oboExchangeTestsContent.Contains('ParentProviderRequestsFmiTokenForConfiguredChild', [StringComparison]::Ordinal)
    $oboChildInfrastructure = $oboConnectionShape -and
        $hostBicepContent -notmatch "Connections__OboServiceConnection__Settings__AgentId" -and
        $hostBicepContent -match "(?s)\{\s*name:\s*'Connections__OboServiceConnection__Settings__ClientId'\s*value:\s*agent365BlueprintId\s*\}" -and
        $hostBicepContent -match "(?s)\{\s*name:\s*'Connections__OboServiceConnection__Settings__FederatedClientId'\s*value:\s*managedIdentityClientId\s*\}" -and
        $hostBicepContent -match "(?s)\{\s*name:\s*'AgentIdentityObo__AgentId'\s*value:\s*agent365AgentIds\.onBehalfOf\s*\}" -and
        $hostBicepContent -match "(?s)\{\s*name:\s*'AgentIdentityObo__BlueprintConnectionName'\s*value:\s*'OboServiceConnection'\s*\}"

    $oboExchangeCallCount = [regex]::Matches(
        $applicationContent,
        '_oboTokenExchange\.ExchangeAsync\s*\(').Count
    $oboRawAssertionCount = [regex]::Matches(
        $applicationContent,
        'UserAuthorization\.GetTurnTokenAsync\s*\(').Count
    $oboAppTokenCallCount = [regex]::Matches(
        $applicationContent,
        '_oboTokenExchange\.AcquireAppTokenAsync\s*\(').Count
    $oboPerResourceExchange = $oboRawAssertionCount -eq 1 -and
        $oboExchangeCallCount -eq 3 -and
        $oboAppTokenCallCount -eq 1 -and
        $applicationContent -match '(?s)oboUserAssertion\s*=\s*await UserAuthorization\.GetTurnTokenAsync\s*\(\s*turnContext\s*,\s*handlers\.FoundryAuthHandlerName' -and
        $applicationContent.Contains('[AgentIdentityAuthorizationScopes.Foundry]', [StringComparison]::Ordinal) -and
        $applicationContent.Contains('[AgentIdentityAuthorizationScopes.GraphDefault]', [StringComparison]::Ordinal) -and
        $applicationContent.Contains('[AgentIdentityAuthorizationScopes.InternalMcpDefault(_internalMcpOptions.Audience)]', [StringComparison]::Ordinal) -and
        $applicationContent -match '(?s)_oboTokenExchange\.AcquireAppTokenAsync\s*\(\s*tenantId\s*,\s*resolvedAgentId\s*,\s*observabilityScopes'

    $appOnlyChildObservability =
        $oboExchangeContent.Contains('.AcquireTokenForClient(scopes)', [StringComparison]::Ordinal) -and
        $oboExchangeTestsContent.Contains('AcquiresAppOnlyChildTokenWithoutUserAssertion', [StringComparison]::Ordinal) -and
        $oboExchangeTestsContent.Contains('RejectsAppOnlyTokenStillMintedForBlueprint', [StringComparison]::Ordinal) -and
        $programContent.Contains('var observabilityTokenCache = new ServiceTokenCache();', [StringComparison]::Ordinal) -and
        $programContent.Contains('AddSingleton<IExporterTokenCache<string>>(observabilityTokenCache)', [StringComparison]::Ordinal) -and
        $programContent.Contains('options.Agent365.TokenResolver = observabilityTokenCache.GetObservabilityToken;', [StringComparison]::Ordinal) -and
        $programContent.Contains('options.Agent365.UseS2SEndpoint = true;', [StringComparison]::Ordinal) -and
        -not $programContent.Contains('AgenticTokenCache', [StringComparison]::Ordinal) -and
        $applicationContent.Contains('IExporterTokenCache<string> _observabilityTokenCache', [StringComparison]::Ordinal) -and
        $applicationContent -match '(?s)_observabilityTokenCache\.RegisterObservability\s*\(\s*resolvedAgentId\s*,\s*tenantId\s*,\s*observabilityToken\s*,\s*observabilityScopes\s*\)' -and
        $observabilityTokenCacheTestsContent.Contains('ConcurrentFrontendsRemainIsolatedByAgentAndTenant', [StringComparison]::Ordinal)

    $authenticatedFrontendIdentityBinding =
        $programContent.Contains('AddSingleton<AgentFrontendIdentityBinding>()', [StringComparison]::Ordinal) -and
        $applicationContent.Contains('_frontendIdentityBinding.Resolve(turnContext.Activity, frontendMode)', [StringComparison]::Ordinal) -and
        $applicationContent.Contains('tenantId = identity.TenantId;', [StringComparison]::Ordinal) -and
        $applicationContent.Contains('resolvedAgentId = identity.AgentId;', [StringComparison]::Ordinal) -and
        $applicationContent.Contains('AgentFrontendIdentityBinding.ValidateAgentToken(token, expectedAgentId)', [StringComparison]::Ordinal) -and
        $frontendIdentityBindingContent.Contains('activity.GetAgenticTenantId()', [StringComparison]::Ordinal) -and
        $frontendIdentityBindingContent.Contains('activity.GetAgenticInstanceId()', [StringComparison]::Ordinal) -and
        $frontendIdentityBindingContent.Contains('claim.Type is "appid" or "azp"', [StringComparison]::Ordinal) -and
        $frontendIdentityBindingTestsContent.Contains('AcceptsAnyValidAgenticChildUnderTheAuthenticatedBlueprint', [StringComparison]::Ordinal) -and
        $frontendIdentityBindingTestsContent.Contains('RejectsActivityForDifferentTenant', [StringComparison]::Ordinal) -and
        $frontendIdentityBindingTestsContent.Contains('RejectsInvalidOboChildSetting', [StringComparison]::Ordinal) -and
        $frontendIdentityBindingTestsContent.Contains('ResourceTokenMustBelongToActivityChild', [StringComparison]::Ordinal) -and
        $frontendIdentityBindingTestsContent.Contains('ConcurrentFrontendsRemainBoundToDistinctChildren', [StringComparison]::Ordinal)

    $mcpTokenAudienceModuleCount = @($mcpContainerModuleContents | Where-Object {
        $_.Contains('param mcpTokenAudience string', [StringComparison]::Ordinal) -and
        $_.Contains("name: 'McpAuthorization__Audience'", [StringComparison]::Ordinal) -and
        $_.Contains('value: mcpTokenAudience', [StringComparison]::Ordinal)
    }).Count
    $mcpV2TokenAudienceBoundary =
        $mcpAuthorizationContent.Contains('Guid.TryParse(Audience, out _)', [StringComparison]::Ordinal) -and
        $mcpAuthorizationTestsContent.Contains('ProductionJwtValidationUsesV2ApplicationIdAudience', [StringComparison]::Ordinal) -and
        $mcpAuthorizationTestsContent.Contains('LocallySignedTokenAcceptsApplicationIdAudience', [StringComparison]::Ordinal) -and
        $mcpAuthorizationTestsContent.Contains('LocallySignedTokenRejectsNonApplicationIdAudience', [StringComparison]::Ordinal) -and
        $mcpApiApplicationBicepContent.Contains('requestedAccessTokenVersion: 2', [StringComparison]::Ordinal) -and
        [regex]::Matches($mainBicepContent, 'mcpTokenAudience:\s*mcpApiApplication\.outputs\.applicationId').Count -eq 4 -and
        [regex]::Matches($mainBicepContent, 'mcpAudience:\s*mcpApiApplication\.outputs\.audience').Count -eq 1 -and
        $mcpTokenAudienceModuleCount -eq 4

    # Destination-scoped tool names change with the product region, so each contract is matched by
    # its stable tool family rather than one hard-coded city name.
    $expectedInternalMcpToolPatterns = @(
        '"search_[a-z0-9]+_attractions"',
        '"get_[a-z0-9]+_current_weather"',
        '"get_[a-z0-9]+_weather_forecast"',
        '"get_[a-z0-9]+_weather_alerts"',
        '"search_[a-z0-9]+_accommodation"',
        '"convert_currency_with_rate"',
        '"get_exchange_rate"',
        '"convert_currency"'
    )
    $schemaFingerprintCount = [regex]::Matches(
        $internalMcpOptionsContent,
        '"[A-F0-9]{64}"').Count
    $allExpectedToolNamesPresent = @($expectedInternalMcpToolPatterns | Where-Object {
        [regex]::IsMatch($internalMcpOptionsContent, $_)
    }).Count -eq $expectedInternalMcpToolPatterns.Count
    $canonicalSchemaFingerprintEnforcement = $schemaFingerprintCount -eq 8 -and
        $allExpectedToolNamesPresent -and
        $internalMcpCatalogContent.Contains('actualNames.SetEquals(expectedNames)', [StringComparison]::Ordinal) -and
        $internalMcpCatalogContent.Contains('StringComparison.Ordinal', [StringComparison]::Ordinal) -and
        $internalMcpCatalogContent.Contains('parameters.SetEquals(contract.Parameters)', [StringComparison]::Ordinal) -and
        $internalMcpCatalogContent.Contains('requiredParameters.SetEquals(contract.RequiredParameters)', [StringComparison]::Ordinal) -and
        $internalMcpCatalogContent.Contains('ComputeSchemaFingerprint(schema)', [StringComparison]::Ordinal) -and
        $internalMcpCatalogContent.Contains('contract.SchemaSha256', [StringComparison]::Ordinal) -and
        $internalMcpCatalogContent.Contains('SHA256.HashData(stream.ToArray())', [StringComparison]::Ordinal) -and
        $internalMcpCatalogContent.Contains('.OrderBy(property => property.Name, StringComparer.Ordinal)', [StringComparison]::Ordinal) -and
        $internalMcpCatalogContent.Contains('WriteCanonical(writer, property.Value)', [StringComparison]::Ordinal) -and
        $internalMcpCatalogContent.Contains('WriteCanonical(writer, item)', [StringComparison]::Ordinal) -and
        $internalMcpCatalogContent.Contains('element.WriteTo(writer)', [StringComparison]::Ordinal) -and
        $internalMcpCatalogTestsContent.Contains('RejectsUnexpectedToolBeforeModelExposure', [StringComparison]::Ordinal) -and
        $internalMcpCatalogTestsContent.Contains('RejectsAlteredNestedSchemaBeforeModelExposure', [StringComparison]::Ordinal)

    $httpsEndpointEntries = @(
        @{ Name = 'Attractions'; Fqdn = 'attractionsFqdn' },
        @{ Name = 'Weather'; Fqdn = 'weatherFqdn' },
        @{ Name = 'Accommodation'; Fqdn = 'accommodationFqdn' },
        @{ Name = 'Currency'; Fqdn = 'currencyFqdn' }
    )
    $httpsEndpointInfrastructureCount = @($httpsEndpointEntries | Where-Object {
        $expectedName = "InternalMcp__$($_.Name)Endpoint"
        $expectedValue = 'https://${' + $_.Fqdn + '}/mcp'
        $entryPattern = "(?s)\{\s*name:\s*'$([regex]::Escape($expectedName))'\s*value:\s*'$([regex]::Escape($expectedValue))'\s*\}"
        $hostBicepContent -match $entryPattern
    }).Count
    $productionMcpHttpsEnforcement =
        $programContent.Contains('options.HasValidEndpoints(requireHttps: !isLocalEnvironment)', [StringComparison]::Ordinal) -and
        $programContent.Contains('All four InternalMcp endpoints must be absolute HTTPS URLs outside local development.', [StringComparison]::Ordinal) -and
        $internalMcpOptionsContent.Contains('public bool HasValidEndpoints(bool requireHttps = false)', [StringComparison]::Ordinal) -and
        $internalMcpOptionsContent -match '(?s)requireHttps\s*\?\s*string\.Equals\(endpoint\.Scheme,\s*"https",\s*StringComparison\.OrdinalIgnoreCase\)' -and
        $httpsEndpointInfrastructureCount -eq 4 -and
        $internalMcpCatalogTestsContent.Contains('ProductionEndpointValidationRejectsPlaintextHttp', [StringComparison]::Ordinal)
    foreach ($sourceCheck in @(
        @{ Name = 'HTTP client factory registration'; Valid = $programContent.Contains('AddHttpClient()', [StringComparison]::Ordinal) },
        @{ Name = 'AgentApplication host'; Valid = $applicationContent.Contains(': AgentApplication', [StringComparison]::Ordinal) },
        @{ Name = 'Protected custom MCP loading'; Valid = $customMcpLoading },
        @{ Name = 'WorkIQ compatibility gate'; Valid = $workIqCompatibilityGate },
        @{ Name = 'Directly referenced runtime dependencies'; Valid = $runtimeDependencyPinning },
        @{ Name = 'Two protected host routes'; Valid = $dualFrontendRoutes },
        @{ Name = 'Frontend channel audience mapping'; Valid = $frontendChannelAudienceMapping }
    )) {
        $results.Add((New-JexValidationResult -Area 'Repository' -Check $sourceCheck.Name `
            -Status $(if ($sourceCheck.Valid) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($sourceCheck.Valid) { 'Required host boundary is present.' } else { 'Required host boundary is missing.' })))
    }

    foreach ($boundaryCheck in @(
        @{
            Name        = 'OBO authorization configuration boundary'
            Valid       = $oboConfigurationBoundary
            PassMessage = 'The sole OBO user handler contains only its Azure Bot OAuth connection setting, with no generic OBO settings in source configuration or Bicep.'
            FailMessage = 'The OBO user handler shape is stale or generic OBO connection/scope settings exist in source configuration or Bicep.'
            Remediation = 'Keep one obo-user AzureBotUserAuthorization handler with only AzureBotOAuthConnectionName and remove OBOConnectionName/OBOScopes.'
            Data        = @{ LegacySettings = @($legacyGenericOboFindings) }
        },
        @{
            Name        = 'Two-stage child Agent Identity OBO'
            Valid       = $twoStageChildExchange -and $oboChildInfrastructure
            PassMessage = 'Parent fmi_path acquisition, child MSAL OBO, token identity validation, and child Bicep selection are present.'
            FailMessage = 'The two-stage child Agent Identity OBO implementation or its child-selection infrastructure is incomplete.'
            Remediation = 'Restore parent IAgenticTokenProvider acquisition, child confidential-client OBO, /.default and child-token checks, and AgentIdentityObo child configuration.'
            Data        = $null
        },
        @{
            Name        = 'OBO per-resource child exchanges'
            Valid       = $oboPerResourceExchange
            PassMessage = 'One raw user assertion feeds delegated child exchanges for Foundry, Graph, and custom MCP; observability uses one app-only child exchange.'
            FailMessage = 'The turn no longer performs the expected three delegated child exchanges and one app-only observability exchange.'
            Remediation = 'Acquire obo-user once for Foundry, Graph, and custom MCP child OBO, and acquire observability through the app-only child path.'
            Data        = @{ DelegatedExchangeCalls = $oboExchangeCallCount; AppTokenCalls = $oboAppTokenCallCount; RawAssertionCalls = $oboRawAssertionCount }
        },
        @{
            Name        = 'App-only child observability'
            Valid       = $appOnlyChildObservability
            PassMessage = 'Both protected frontend modes use one app-only child token cache and the Agent 365 S2S observability endpoint.'
            FailMessage = 'The shared app-only child observability path or S2S exporter configuration is incomplete.'
            Remediation = 'Acquire child tokens with AcquireTokenForClient, use one IExporterTokenCache<string>, and enable Agent365.UseS2SEndpoint.'
            Data        = $null
        },
        @{
            Name        = 'Authenticated frontend identity binding'
            Valid       = $authenticatedFrontendIdentityBinding
            PassMessage = 'Each protected route binds tenant and downstream token selection to its authenticated child audience, including concurrent frontend tests.'
            FailMessage = 'Downstream identity can diverge from the tenant or child audience authenticated by the frontend route.'
            Remediation = 'Resolve protected turn identity from TokenValidation settings, reject activity mismatches, and keep OBO AgentId equal to its route audience.'
            Data        = $null
        },
        @{
            Name        = 'MCP v2 token audience boundary'
            Valid       = $mcpV2TokenAudienceBoundary
            PassMessage = 'MCP services validate the v2 token application ID while the host requests the identifier-URI delegated scope.'
            FailMessage = 'MCP token validation conflates the v2 application ID audience with the delegated scope identifier URI.'
            Remediation = 'Pass the MCP API applicationId to service JWT validation and retain the identifier URI only for host scope acquisition.'
            Data        = $null
        },
        @{
            Name        = 'Canonical MCP schema fingerprints'
            Valid       = $canonicalSchemaFingerprintEnforcement
            PassMessage = 'All eight tool contracts have full SHA-256 fingerprints enforced over recursively canonicalized input schemas.'
            FailMessage = 'The eight-contract schema fingerprint set or canonical enforcement logic is incomplete.'
            Remediation = 'Restore all eight 64-hex fingerprints and exact tool-set, property-set, description, and recursive canonical schema checks.'
            Data        = @{ FingerprintCount = $schemaFingerprintCount }
        },
        @{
            Name        = 'Production MCP HTTPS endpoint enforcement'
            Valid       = $productionMcpHttpsEnforcement
            PassMessage = 'Non-local options require HTTPS and Bicep supplies HTTPS endpoints for all four internal MCP services.'
            FailMessage = 'Production HTTPS validation or one of the four HTTPS MCP endpoint settings is missing.'
            Remediation = 'Require HTTPS outside local environments and keep every InternalMcp endpoint in Bicep on https://.'
            Data        = @{ HttpsBicepEndpoints = $httpsEndpointInfrastructureCount }
        }
    )) {
        $results.Add((New-JexValidationResult -Area 'Repository' -Check $boundaryCheck.Name `
            -Status $(if ($boundaryCheck.Valid) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($boundaryCheck.Valid) { $boundaryCheck.PassMessage } else { $boundaryCheck.FailMessage }) `
            -Remediation $(if ($boundaryCheck.Valid) { '' } else { $boundaryCheck.Remediation }) `
            -Data $boundaryCheck.Data))
    }

    $readmePath = Join-Path $root 'README.md'
    $readmeFirstLine = if (Test-Path -LiteralPath $readmePath) { Get-Content -LiteralPath $readmePath -TotalCount 1 } else { '' }
    $readmeValid = $readmeFirstLine -match '^#\s+\S.*Backend\s*$'
    $results.Add((New-JexValidationResult -Area 'Repository' -Check 'README identity' `
        -Status $(if ($readmeValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($readmeValid) { 'README opens with a single backend title heading.' } else { 'README is stale, missing, or contains a merge artifact.' }) `
        -Remediation $(if ($readmeValid) { '' } else { 'Start README.md with one product backend title heading.' })))

    if ($null -ne $milestone -and $milestone.Current.id -eq 'M0') {
        $implementationFiles = @(
            (Get-Item -LiteralPath (Join-Path $root 'Directory.Packages.props'))
            Get-JexFirstPartyFiles -Path (Join-Path $root 'server') -Extension @('.cs', '.csproj', '.props')
        )
        $implementationMarkers = @($implementationFiles | ForEach-Object {
            $relativePath = [IO.Path]::GetRelativePath($root, $_.FullName)
            Find-JexM0ImplementationMarker -Content (Get-Content -LiteralPath $_.FullName -Raw) -Source $relativePath
        })
        $m0Clean = $implementationMarkers.Count -eq 0
        $results.Add((New-JexValidationResult -Area 'Repository' -Check 'M0 onboarding boundary' `
            -Status $(if ($m0Clean) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($m0Clean) { 'Purview implementation remains deferred to M1.' } else { 'M1 implementation markers exist while M0 is active.' }) `
            -Remediation $(if ($m0Clean) { '' } else { 'Review the milestone transition before retaining M1 artifacts.' }) `
            -Data @{ ImplementationMarkers = @($implementationMarkers) }))
    }

    $toolMutationFindings = @(Get-ChildItem -LiteralPath (Join-Path $root 'tools') -Recurse -File |
        Where-Object {
            $_.FullName -notmatch '[\\/]node_modules[\\/]' -and
            $_.Extension -in @('.ps1', '.psm1')
        } |
        ForEach-Object {
            Find-JexForbiddenToolMutation `
                -Content (Get-Content -LiteralPath $_.FullName -Raw) `
                -Source ([IO.Path]::GetRelativePath($root, $_.FullName))
        })
    $results.Add((New-JexValidationResult -Area 'Repository' -Check 'Validation tool mutation safety' `
        -Status $(if ($toolMutationFindings.Count -eq 0) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($toolMutationFindings.Count -eq 0) { 'Validation tools contain no recognized cloud mutation command.' } else { 'Validation tools contain a recognized cloud mutation command.' }) `
        -Remediation $(if ($toolMutationFindings.Count -eq 0) { '' } else { 'Remove mutation commands from tools; keep setup and policy changes in approved milestone workflows.' }) `
        -Data @{ Findings = @($toolMutationFindings) }))

    $secretFindings = @(Find-JexPotentialSecrets -RepositoryRoot $root)
    $results.Add((New-JexValidationResult -Area 'Repository' -Check 'Secret hygiene' `
        -Status $(if ($secretFindings.Count -eq 0) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($secretFindings.Count -eq 0) { 'No obvious committed secret assignments were found.' } else { 'Potential secret values were found.' }) `
        -Remediation $(if ($secretFindings.Count -eq 0) { '' } else { 'Remove values and rotate any exposed credentials.' }) `
        -Data @{ Files = @($secretFindings) }))

    $identifierFindings = @(Find-JexCommittedIdentifier -RepositoryRoot $root)
    $results.Add((New-JexValidationResult -Area 'Repository' -Check 'Committed identifier hygiene' `
        -Status $(if ($identifierFindings.Count -eq 0) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($identifierFindings.Count -eq 0) { 'No subscription, tenant, principal, mailbox, or full resource identifier is committed to source.' } else { 'A tenant-bound identifier is committed to source.' }) `
        -Remediation $(if ($identifierFindings.Count -eq 0) { '' } else { 'Replace the identifier with a command parameter or placeholder. Only fixed non-secret names such as the target resource group, Foundry account and project, its endpoint, and the model deployment may be committed.' }) `
        -Data @{ Findings = @($identifierFindings) }))

    $casePolicy = Get-JexSyntheticCasePolicy -RepositoryRoot $root
    $syntheticFindings = @(Find-JexSyntheticSensitiveData -RepositoryRoot $root)
    $syntheticValid = $casePolicy.IsConsistent -and $syntheticFindings.Count -eq 0
    $results.Add((New-JexValidationResult -Area 'Repository' -Check 'Synthetic sensitive-data cases' `
        -Status $(if ($syntheticValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($syntheticValid) { "Milestone $($casePolicy.MilestoneId) declares exactly the three reserved synthetic cases and no backend source carries a sensitive-data literal outside the reserved ranges." } else { 'The active milestone does not declare the three reserved synthetic cases, still declares a retired case, or backend source carries a sensitive-data literal outside the reserved ranges.' }) `
        -Remediation $(if ($syntheticValid) { '' } else { 'Declare the Japan passport, Japanese residence card, and reserved test card cases in the active milestone, remove retired cases, and keep exact test values only in the Direct Line frontend fixture.' }) `
        -Data @{
            MilestoneId     = $casePolicy.MilestoneId
            ExpectedCases   = @($casePolicy.ExpectedCases)
            MissingCases    = @($casePolicy.MissingCases)
            RetiredDeclared = @($casePolicy.RetiredDeclared)
            Findings        = @($syntheticFindings)
        }))

    $symbolFindings = @(Find-JexRetiredSymbol -RepositoryRoot $root)
    $toolFileCount = @(Get-ChildItem -LiteralPath (Join-Path $root 'tools') -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.ps1', '.psm1') }).Count
    if ($toolFileCount -eq 0) {
        $results.Add((New-JexValidationResult -Area 'Repository' -Check 'Validation symbol prefix' -Status 'Skip' `
            -Message 'No validation tool scripts are present in this tree, so the symbol prefix was not evaluated.'))
    }
    else {
        $symbolsValid = $symbolFindings.Count -eq 0
        $results.Add((New-JexValidationResult -Area 'Repository' -Check 'Validation symbol prefix' `
            -Status $(if ($symbolsValid) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($symbolsValid) { "All $toolFileCount validation tool scripts define, export, and call functions under the Jex prefix, with no retired product acronym." } else { 'A validation symbol still uses a retired product acronym or a non-Jex module prefix.' }) `
            -Remediation $(if ($symbolsValid) { '' } else { 'Rename the symbol to the Jex prefix and update every definition, export, and caller.' }) `
            -Data @{ ToolScriptCount = $toolFileCount; Findings = @($symbolFindings) }))
    }

    @($results)
}

function Find-JexRetiredSymbol {
    <#
        .SYNOPSIS
        Finds validation symbols that still carry a retired product acronym or a non-Jex prefix.

        .DESCRIPTION
        The validation surface is named for the current product. Matching is case sensitive so English
        words such as "two-stage" and resource names such as id-stay are not mistaken for the retired
        Seoul Tourist Agent acronym. Test-harness helpers local to the self-test runner are allowed,
        because they are not part of the validation API.
    #>
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $toolsDirectory = Join-Path $root 'tools'
    if (-not (Test-Path -LiteralPath $toolsDirectory -PathType Container)) {
        return
    }

    $allowedNonPrefixedFunctions = @('Assert-ToolsCondition', 'Get-SelfTestRelativePath')
    $modulePath = Join-Path $toolsDirectory 'modules\JapanExpert.Validation\JapanExpert.Validation.psm1'
    $toolFiles = @(Get-ChildItem -LiteralPath $toolsDirectory -Recurse -File | Where-Object {
        $_.Extension -in @('.ps1', '.psm1')
    })

    foreach ($file in $toolFiles) {
        $relativePath = [IO.Path]::GetRelativePath($root, $file.FullName)
        $isModule = $file.FullName -eq $modulePath
        $lineNumber = 0
        foreach ($line in @(Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue)) {
            $lineNumber++
            foreach ($match in [regex]::Matches($line, '(?<![A-Za-z])[A-Za-z]+-Sta[A-Z]')) {
                [pscustomobject]@{ Path = $relativePath; Line = $lineNumber; Rule = 'retired product acronym' }
            }
            foreach ($match in [regex]::Matches($line, '^\s*function\s+(?<name>[A-Za-z]+-[A-Za-z0-9]+)')) {
                $functionName = $match.Groups['name'].Value
                if ($functionName -in $allowedNonPrefixedFunctions) {
                    continue
                }
                if ($functionName -notmatch '^[A-Za-z]+-Jex[A-Z]') {
                    [pscustomobject]@{ Path = $relativePath; Line = $lineNumber; Rule = 'function outside the Jex prefix' }
                }
            }
            if ($isModule) {
                $exportMatch = [regex]::Match($line, "^\s*'(?<name>[A-Za-z]+-[A-Za-z0-9]+)',?\s*$")
                if ($exportMatch.Success -and $exportMatch.Groups['name'].Value -notmatch '^[A-Za-z]+-Jex[A-Z]') {
                    [pscustomobject]@{ Path = $relativePath; Line = $lineNumber; Rule = 'export outside the Jex prefix' }
                }
            }
        }
    }
}

function Get-JexSecretStoreRequirement {
    <#
        .SYNOPSIS
        Reports whether any first-party source actually reads a managed secret store.

        .DESCRIPTION
        M8 deploys only what current source requires. Infrastructure may declare a Key Vault only when
        a workload reads secrets from one, so this reads the server tree instead of hard-coding the
        answer. If a provider later needs a secret client, the rule relaxes automatically.
    #>
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $consumers = @(Get-JexFirstPartyFiles -Path (Join-Path $root 'server') -Extension @('.cs', '.csproj') |
        Where-Object {
            (Get-Content -LiteralPath $_.FullName -Raw) -match 'SecretClient|Azure\.Security\.KeyVault|KeyVaultSecret'
        } |
        ForEach-Object { [IO.Path]::GetRelativePath($root, $_.FullName) })

    [pscustomobject]@{
        RequiresSecretStore = $consumers.Count -gt 0
        Consumers           = @($consumers)
    }
}

function Test-JexDeploymentBoundary {
    <#
        .SYNOPSIS
        Offline structural validation of the backend deployment boundary.

        .DESCRIPTION
        Asserts that the checked-in infrastructure can only deploy into the single approved backend
        resource group, references the existing Foundry account across resource groups instead of
        recreating it, uses deterministic Japan Tourist Assistant resource names, and no longer carries retired
        Seoul deployment names. Every check reads local files only; no Azure call is made.
    #>
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $results = [System.Collections.Generic.List[object]]::new()
    $policy = Get-JexDeploymentPolicy -RepositoryRoot $root
    $infraDirectory = Join-Path $root 'infra'

    if (-not (Test-Path -LiteralPath $infraDirectory -PathType Container)) {
        return ,(New-JexValidationResult -Area 'Deployment' -Check 'Infrastructure source' -Status 'Fail' `
            -Message 'The infra directory is missing.' `
            -Remediation 'Restore infra/ from the canonical backend before validating deployment scope.')
    }

    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Milestone deployment policy' `
        -Status $(if ($policy.IsConsistent) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($policy.IsConsistent) { "Milestone $($policy.MilestoneId) states the approved resource group, Foundry account, project, and model deployment used by these checks." } else { 'The milestone manifest no longer states the deployment targets these checks enforce.' }) `
        -Remediation $(if ($policy.IsConsistent) { '' } else { 'Reconcile docs/milestones/milestones.json with the approved deployment targets before deploying.' }) `
        -Data @{
            MilestoneId             = $policy.MilestoneId
            ApprovedResourceGroup   = $policy.ApprovedResourceGroup
            FoundryResourceGroup    = $policy.FoundryResourceGroup
            FoundryAccountName      = $policy.FoundryAccountName
            FoundryProjectName      = $policy.FoundryProjectName
            ModelDeploymentName     = $policy.ModelDeploymentName
            MissingManifestValues   = @($policy.MissingManifestValues)
        }))

    $bicepFiles = @(Get-ChildItem -LiteralPath $infraDirectory -Recurse -File -Filter '*.bicep')
    $jsonFiles = @(Get-ChildItem -LiteralPath $infraDirectory -Recurse -File -Filter '*.json' |
        Where-Object { $_.Name -ne 'bicepconfig.json' })
    $deploymentFiles = @($bicepFiles + $jsonFiles)
    $fileContent = [ordered]@{}
    foreach ($file in $deploymentFiles) {
        $fileContent[[IO.Path]::GetRelativePath($root, $file.FullName)] = (Get-Content -LiteralPath $file.FullName -Raw)
    }

    $entryTemplates = @('infra\main.bicep', 'infra\live-backend-container-apps-update.bicep')
    $missingEntryTemplates = @($entryTemplates | Where-Object { -not $fileContent.Contains($_) })
    if ($missingEntryTemplates.Count -gt 0) {
        $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Deployment templates' -Status 'Fail' `
            -Message 'A required deployment template is missing.' `
            -Remediation 'Restore the bootstrap and existing-backend update templates.' `
            -Data @{ MissingTemplates = @($missingEntryTemplates) }))
        return @($results)
    }

    $nonResourceGroupScopes = @(
        foreach ($entry in $fileContent.GetEnumerator()) {
            foreach ($match in [regex]::Matches($entry.Value, "(?m)^\s*targetScope\s*=\s*'(?<scope>[a-zA-Z]+)'")) {
                if ($match.Groups['scope'].Value -ne 'resourceGroup') {
                    [pscustomobject]@{ Path = $entry.Key; Scope = $match.Groups['scope'].Value }
                }
            }
        }
    )
    $entryScopeDeclared = @($entryTemplates | Where-Object {
        $fileContent[$_] -match "(?m)^\s*targetScope\s*=\s*'resourceGroup'"
    }).Count -eq $entryTemplates.Count
    $scopeValid = $entryScopeDeclared -and $nonResourceGroupScopes.Count -eq 0
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Resource group deployment scope' `
        -Status $(if ($scopeValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($scopeValid) { 'Both entry templates declare resourceGroup scope and no template declares a wider scope.' } else { 'A deployment template is missing resourceGroup scope or declares a subscription, management group, or tenant scope.' }) `
        -Remediation $(if ($scopeValid) { '' } else { "Declare targetScope = 'resourceGroup' in every deployment template." }) `
        -Data @{ WiderScopes = @($nonResourceGroupScopes) }))

    $resourceGroupCreators = @(
        foreach ($entry in $fileContent.GetEnumerator()) {
            if ($entry.Value -match "(?i)Microsoft\.Resources/resourceGroups") {
                [pscustomobject]@{ Path = $entry.Key }
            }
        }
    )
    $subscriptionScopedModules = @(
        foreach ($entry in $fileContent.GetEnumerator()) {
            foreach ($match in [regex]::Matches($entry.Value, "(?m)^\s*scope:\s*(?<target>subscription\(|managementGroup\(|tenant\()")) {
                [pscustomobject]@{ Path = $entry.Key; Scope = $match.Groups['target'].Value }
            }
        }
    )
    $noResourceGroupCreation = $resourceGroupCreators.Count -eq 0 -and $subscriptionScopedModules.Count -eq 0
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'No resource group creation' `
        -Status $(if ($noResourceGroupCreation) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($noResourceGroupCreation) { 'No template declares a resource group resource or deploys above resource-group scope.' } else { 'A template can create a resource group or deploy above resource-group scope.' }) `
        -Remediation $(if ($noResourceGroupCreation) { '' } else { 'Remove Microsoft.Resources/resourceGroups declarations and subscription, management group, or tenant scoped deployments.' }) `
        -Data @{ ResourceGroupDeclarations = @($resourceGroupCreators); WiderScopedDeployments = @($subscriptionScopedModules) }))

    $allowedResourceGroups = @($policy.ApprovedResourceGroup, $policy.FoundryResourceGroup)
    $unexpectedResourceGroups = @(
        foreach ($entry in $fileContent.GetEnumerator()) {
            foreach ($match in [regex]::Matches($entry.Value, '(?i)\brg-[a-z0-9][a-z0-9-]*')) {
                if ($match.Value.ToLowerInvariant() -notin @($allowedResourceGroups | ForEach-Object { $_.ToLowerInvariant() })) {
                    [pscustomobject]@{ Path = $entry.Key; ResourceGroup = $match.Value }
                }
            }
        }
    )
    $approvedGroupPinned = $fileContent['infra\main.bicep'] -match "@allowed\(\s*\[\s*'$([regex]::Escape($policy.ApprovedResourceGroup))'\s*\]\s*\)" -and
        $fileContent['infra\main.bicep'] -match 'approvedDeploymentScopes\[toLower\(resourceGroup\(\)\.name\)\]'
    $updateGroupPinned = $fileContent['infra\live-backend-container-apps-update.bicep'] -match "@allowed\(\s*\[\s*'$([regex]::Escape($policy.ApprovedResourceGroup))'\s*\]\s*\)" -and
        $fileContent['infra\live-backend-container-apps-update.bicep'] -match 'approvedDeploymentScopes\[toLower\(resourceGroup\(\)\.name\)\]'
    $singleGroupTarget = $approvedGroupPinned -and $updateGroupPinned -and $unexpectedResourceGroups.Count -eq 0
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Approved resource group target' `
        -Status $(if ($singleGroupTarget) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($singleGroupTarget) { "Both entry templates pin and guard $($policy.ApprovedResourceGroup), and reference no resource group other than the existing Foundry group." } else { 'A deployment template does not pin and guard the approved resource group, or it references another resource group.' }) `
        -Remediation $(if ($singleGroupTarget) { '' } else { "Restore the allowed-value parameter and deployment guard for $($policy.ApprovedResourceGroup) and remove other resource group references." }) `
        -Data @{
            ApprovedResourceGroup    = $policy.ApprovedResourceGroup
            AllowedResourceGroups    = @($allowedResourceGroups)
            UnexpectedResourceGroups = @($unexpectedResourceGroups)
        }))

    $foundryCreations = @(
        foreach ($entry in $fileContent.GetEnumerator()) {
            foreach ($match in [regex]::Matches(
                $entry.Value,
                "(?m)^\s*resource\s+\w+\s+'Microsoft\.CognitiveServices/[^']+'\s*=\s*\{")) {
                [pscustomobject]@{ Path = $entry.Key; Declaration = $match.Value.Trim() }
            }
        }
    )
    $mainBicep = $fileContent['infra\main.bicep']
    $foundryReferenced = $mainBicep -match "resource\s+existingFoundryAccount\s+'Microsoft\.CognitiveServices/accounts@[^']+'\s+existing\s*=" -and
        $mainBicep -match 'scope:\s*resourceGroup\(foundryResourceGroupName\)' -and
        $mainBicep -match "param foundryResourceGroupName string = '$([regex]::Escape($policy.FoundryResourceGroup))'" -and
        $mainBicep -match "param foundryAccountName string = '$([regex]::Escape($policy.FoundryAccountName))'" -and
        $mainBicep -match "param foundryProjectName string = '$([regex]::Escape($policy.FoundryProjectName))'" -and
        $mainBicep -match "param foundryModelDeploymentName string = '$([regex]::Escape($policy.ModelDeploymentName))'"
    $foundryValid = $foundryReferenced -and $foundryCreations.Count -eq 0
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Existing Foundry cross-group reference' `
        -Status $(if ($foundryValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($foundryValid) { "The existing $($policy.FoundryAccountName) account, $($policy.FoundryProjectName) project, and $($policy.ModelDeploymentName) deployment are referenced in $($policy.FoundryResourceGroup) and never created." } else { 'Foundry is created, moved, or no longer referenced as an existing cross-resource-group resource.' }) `
        -Remediation $(if ($foundryValid) { '' } else { 'Reference the existing Foundry account with scope: resourceGroup(foundryResourceGroupName) and remove every Microsoft.CognitiveServices resource declaration.' }) `
        -Data @{ FoundryResourceDeclarations = @($foundryCreations) }))

    $expectedNames = Get-JexExpectedDeploymentNames -ResourceBaseName $policy.ResourceBaseName
    $nameFindings = @(
        foreach ($expected in $expectedNames) {
            $pattern = "param\s+$([regex]::Escape($expected.Parameter))\s+string\s*=\s*'$([regex]::Escape($expected.Default))'"
            $inMain = $mainBicep -match $pattern
            $inUpdate = $fileContent['infra\live-backend-container-apps-update.bicep'] -match $pattern
            [pscustomobject]@{
                Parameter          = $expected.Parameter
                ExpectedDefault    = $expected.Default
                ResolvedName       = $expected.ResolvedName
                NameLength         = $expected.ResolvedName.Length
                MaximumNameLength  = $expected.MaximumLength
                WithinAzureLimit   = $expected.ResolvedName.Length -le $expected.MaximumLength
                InBootstrap        = [bool]$inMain
                InUpdateTemplate   = ($expected.UpdateTemplate -eq $false) -or [bool]$inUpdate
            }
        }
    )
    $nameFailures = @($nameFindings | Where-Object {
        -not $_.WithinAzureLimit -or -not $_.InBootstrap -or -not $_.InUpdateTemplate
    })
    $namingValid = $nameFailures.Count -eq 0
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Japan Tourist Assistant resource naming' `
        -Status $(if ($namingValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($namingValid) { "All $($nameFindings.Count) resource names default to deterministic $($policy.ResourceBaseName) values within their Azure length limits." } else { 'A resource name default is missing, inconsistent between templates, or outside its Azure length limit.' }) `
        -Remediation $(if ($namingValid) { '' } else { 'Restore the deterministic name parameter defaults in both deployment templates.' }) `
        -Data @{ ResourceNames = @($nameFindings); Failures = @($nameFailures) }))

    $registryModulePath = 'infra\modules\container-registry.bicep'
    $registryUsesBasic = $mainBicep -match "param\s+containerRegistrySkuName\s+string\s*=\s*'Basic'" -and
        $fileContent.Contains($registryModulePath) -and
        $fileContent[$registryModulePath] -match "param\s+skuName\s+string\s*=\s*'Basic'"
    $mcpReplicaModules = @(
        'infra\modules\attractions-mcp-container-app.bicep',
        'infra\modules\weather-mcp-container-app.bicep',
        'infra\modules\accommodation-mcp-container-app.bicep',
        'infra\modules\currency-mcp-container-app.bicep'
    )
    $mcpReplicaFindings = @(
        foreach ($modulePath in $mcpReplicaModules) {
            [pscustomobject]@{
                Path       = $modulePath
                Exists     = $fileContent.Contains($modulePath)
                OneReplica = $fileContent.Contains($modulePath) -and
                    $fileContent[$modulePath] -match '(?m)^\s*maxReplicas:\s*1\s*$'
            }
        }
    )
    $secretStore = Get-JexSecretStoreRequirement -RepositoryRoot $root
    $keyVaultFindings = @(
        foreach ($entry in $fileContent.GetEnumerator()) {
            if ($entry.Value -match '(?i)Microsoft\.KeyVault/|modules[\\/]key-vault|param\s+\w*keyVault\w*\s') {
                [pscustomobject]@{ Path = $entry.Key }
            }
        }
    )
    $costBoundaryProblems = [System.Collections.Generic.List[string]]::new()
    if (-not $registryUsesBasic) {
        $costBoundaryProblems.Add('the registry does not default to Basic in both the entry template and module')
    }
    if (@($mcpReplicaFindings | Where-Object { -not $_.OneReplica }).Count -gt 0) {
        $costBoundaryProblems.Add('one or more MCP Container Apps do not cap maximum replicas at one')
    }
    if ($keyVaultFindings.Count -gt 0 -and -not $secretStore.RequiresSecretStore) {
        $costBoundaryProblems.Add('infrastructure declares a Key Vault although no first-party source reads a secret store')
    }
    if ($keyVaultFindings.Count -eq 0 -and $secretStore.RequiresSecretStore) {
        $costBoundaryProblems.Add('a first-party source reads a secret store but infrastructure declares no Key Vault')
    }
    $costBoundaryValid = $costBoundaryProblems.Count -eq 0
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Cost and secret-store boundary' `
        -Status $(if ($costBoundaryValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($costBoundaryValid) { "The registry defaults to Basic, every public-provider MCP app is capped at one replica, and the secret-store surface matches source: $(if ($secretStore.RequiresSecretStore) { 'a secret consumer exists and a Key Vault is declared' } else { 'no source reads a secret store and no Key Vault is declared' })." } else { 'The deployment cost or secret-store boundary drifted from what current source requires.' }) `
        -Remediation $(if ($costBoundaryValid) { '' } else { 'Restore the Basic registry default, cap each MCP app at one replica, and keep the Key Vault surface equal to what first-party source actually reads.' }) `
        -Data @{
            Problems            = @($costBoundaryProblems)
            RegistryUsesBasic   = [bool]$registryUsesBasic
            McpReplicaSettings  = @($mcpReplicaFindings)
            KeyVaultFindings    = @($keyVaultFindings)
            RequiresSecretStore = [bool]$secretStore.RequiresSecretStore
            SecretConsumers     = @($secretStore.Consumers)
        }))

    # Zero orphan modules. Every module file must be reachable from an entry template, so deleted
    # capability cannot survive as stale plumbing that a later change silently re-enables.
    $moduleDirectory = Join-Path $root 'infra\modules'
    $referencedModules = @(
        foreach ($templatePath in $entryTemplates) {
            foreach ($match in [regex]::Matches($fileContent[$templatePath], "\./modules/(?<module>[A-Za-z0-9-]+)\.bicep")) {
                $match.Groups['module'].Value
            }
        }
    ) | Sort-Object -Unique
    $orphanModules = @()
    if (Test-Path -LiteralPath $moduleDirectory -PathType Container) {
        $orphanModules = @(Get-ChildItem -LiteralPath $moduleDirectory -File -Filter '*.bicep' |
            Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) -notin $referencedModules } |
            ForEach-Object { [IO.Path]::GetRelativePath($root, $_.FullName) })
    }
    $moduleReferencesValid = $orphanModules.Count -eq 0 -and @($referencedModules).Count -gt 0
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Deployment module references' `
        -Status $(if ($moduleReferencesValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($moduleReferencesValid) { "All $(@($referencedModules).Count) infrastructure modules are reachable from an entry template, so the deployment creates only what current source requires." } else { 'An infrastructure module is unreferenced, so the deployment source retains stale plumbing.' }) `
        -Remediation $(if ($moduleReferencesValid) { '' } else { 'Delete the unreferenced module instead of retaining it as optional plumbing, or wire it into an entry template.' }) `
        -Data @{
            ReferencedModules = @($referencedModules)
            OrphanModules     = @($orphanModules)
        }))

    # Active documentation currency. Guidance this project owns must speak for the current milestone.
    # An earlier milestone may appear only as an explicitly historical reference, a milestone range, or
    # a link to that milestone's record.
    $ownedGuidanceDocs = @('infra\README.md', 'tools\README.md')
    $currentMilestoneId = $policy.MilestoneId
    $staleMilestoneFindings = [System.Collections.Generic.List[object]]::new()
    $documentedCurrent = [System.Collections.Generic.List[string]]::new()
    $presentGuidanceDocs = @($ownedGuidanceDocs | Where-Object {
        Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf
    })
    foreach ($docPath in $presentGuidanceDocs) {
        $lineNumber = 0
        $mentionsCurrent = $false
        foreach ($line in @(Get-Content -LiteralPath (Join-Path $root $docPath) -ErrorAction SilentlyContinue)) {
            $lineNumber++
            $isHistorical = $line -match '(?i)historical|historic\b|record|checkpoint|retired|superseded|previous' -or
                $line -match 'M\d+\s*-\s*M\d+' -or
                $line -match 'docs/milestones/M\d+'
            foreach ($match in [regex]::Matches($line, '(?<![A-Za-z0-9])M(?<number>\d+)(?![A-Za-z0-9])')) {
                $mentioned = "M$($match.Groups['number'].Value)"
                if ($mentioned -eq $currentMilestoneId) {
                    $mentionsCurrent = $true
                    continue
                }
                if (-not $isHistorical) {
                    $staleMilestoneFindings.Add([pscustomobject]@{
                        Path      = $docPath
                        Line      = $lineNumber
                        Milestone = $mentioned
                    })
                }
            }
        }
        if ($mentionsCurrent) {
            $documentedCurrent.Add($docPath)
        }
    }
    $milestoneDocsValid = $presentGuidanceDocs.Count -gt 0 -and
        $staleMilestoneFindings.Count -eq 0 -and
        $documentedCurrent.Count -eq $presentGuidanceDocs.Count
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Active milestone documentation' `
        -Status $(if ($milestoneDocsValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($milestoneDocsValid) { "Deployment and validation guidance states $currentMilestoneId, and every earlier milestone appears only as an explicitly historical reference." } else { "Owned guidance does not state $currentMilestoneId, or an earlier milestone appears as current guidance." }) `
        -Remediation $(if ($milestoneDocsValid) { '' } else { 'Migrate active guidance to the current milestone and label every earlier milestone reference as historical.' }) `
        -Data @{
            CurrentMilestone      = $currentMilestoneId
            CheckedDocuments      = @($presentGuidanceDocs)
            DocumentsStatingCurrent = @($documentedCurrent)
            StaleReferences       = @($staleMilestoneFindings)
        }))

    $retiredNamePattern = '(?i)seoultour|seoul-tourist|seoultourist|kc-ae23|koreaexim|kto-service-key'
    $retiredNameFindings = @(
        foreach ($entry in $fileContent.GetEnumerator()) {
            foreach ($match in [regex]::Matches($entry.Value, $retiredNamePattern)) {
                [pscustomobject]@{ Path = $entry.Key; Token = $match.Value }
            }
        }
    )
    $retiredNamesRemoved = $retiredNameFindings.Count -eq 0
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Retired Seoul deployment names' `
        -Status $(if ($retiredNamesRemoved) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($retiredNamesRemoved) { 'No deployment template or parameter file contains a retired Seoul deployment name.' } else { 'A deployment template or parameter file still contains a retired Seoul deployment name.' }) `
        -Remediation $(if ($retiredNamesRemoved) { '' } else { 'Remove retired Seoul resource names from executable deployment files; keep them only in explicitly historical documentation.' }) `
        -Data @{ Findings = @($retiredNameFindings) }))

    $compiledPath = 'infra\live-backend-container-apps-update.json'
    $compiledParity = $false
    $parityData = @{}
    if ($fileContent.Contains($compiledPath)) {
        $bicepParameters = @([regex]::Matches(
            $fileContent['infra\live-backend-container-apps-update.bicep'],
            '(?m)^param\s+(?<name>\w+)\s') | ForEach-Object { $_.Groups['name'].Value } | Sort-Object -Unique)
        $compiledParameters = @()
        try {
            $compiledTemplate = $fileContent[$compiledPath] | ConvertFrom-Json -Depth 40
            if ($null -ne $compiledTemplate.PSObject.Properties['parameters']) {
                $compiledParameters = @($compiledTemplate.parameters.PSObject.Properties.Name | Sort-Object -Unique)
            }
        }
        catch {
            $compiledParameters = @()
        }
        $missingInCompiled = @($bicepParameters | Where-Object { $_ -notin $compiledParameters })
        $extraInCompiled = @($compiledParameters | Where-Object { $_ -notin $bicepParameters })
        $compiledParity = $bicepParameters.Count -gt 0 -and
            $missingInCompiled.Count -eq 0 -and
            $extraInCompiled.Count -eq 0
        $parityData = @{
            BicepParameterCount    = $bicepParameters.Count
            CompiledParameterCount = $compiledParameters.Count
            MissingInCompiled      = @($missingInCompiled)
            ExtraInCompiled        = @($extraInCompiled)
        }
    }
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Compiled update template parity' `
        -Status $(if ($compiledParity) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($compiledParity) { 'The checked-in compiled update template exposes exactly the parameters declared by its Bicep source.' } else { 'The checked-in compiled update template is missing or out of sync with its Bicep source.' }) `
        -Remediation $(if ($compiledParity) { '' } else { 'Recompile infra/live-backend-container-apps-update.bicep to its checked-in JSON before review.' }) `
        -Data $parityData))

    foreach ($providerResult in @(Test-JexMcpProviderConfiguration `
        -RepositoryRoot $root `
        -FileContent $fileContent)) {
        $results.Add($providerResult)
    }

    # Agent 365 identity ownership. The CLI owns the Blueprint, its child identities, and its
    # federated identity credentials. Infrastructure may create the workload managed identities and
    # the separate MCP resource API, and must publish the host principal ID for the CLI handoff, but
    # it must never declare a Blueprint, an agent identity, or a federated identity credential.
    # Only declared resource types are inspected, so host configuration keys such as
    # AgentIdentityObo__AgentId are correctly treated as settings rather than identity objects.
    $forbiddenTypePattern = '(?i)federatedidentitycredential|agentidentity|blueprint'
    $identityOwnershipFindings = @(
        foreach ($entry in $fileContent.GetEnumerator()) {
            $declaredTypes = @()
            if ($entry.Key -like '*.bicep') {
                $declaredTypes = @([regex]::Matches($entry.Value, "(?m)^\s*resource\s+\w+\s+'(?<type>[^'@]+)") |
                    ForEach-Object { $_.Groups['type'].Value })
            }
            else {
                $declaredTypes = @([regex]::Matches($entry.Value, '"type"\s*:\s*"(?<type>[^"]+)"') |
                    ForEach-Object { $_.Groups['type'].Value })
            }
            foreach ($declaredType in @($declaredTypes | Sort-Object -Unique)) {
                if ($declaredType -match $forbiddenTypePattern) {
                    [pscustomobject]@{ Path = $entry.Key; Declaration = $declaredType }
                }
            }
        }
    )
    $publishesHostPrincipalId = $mainBicep -match '(?m)^output\s+hostManagedIdentityPrincipalId\s+string\s*='
    # The credential itself is an approved Graph step. The runbook must document its exact shape so the
    # reviewed mutation cannot drift from the identity model the host depends on.
    $identityRunbookProblems = [System.Collections.Generic.List[string]]::new()
    $runbookPath = Join-Path $root 'infra\README.md'
    if (Test-Path -LiteralPath $runbookPath -PathType Leaf) {
        $runbookText = Get-Content -LiteralPath $runbookPath -Raw
        foreach ($requirement in @(
            @{ Name = 'the federatedIdentityCredentials Graph endpoint'; Pattern = '(?i)applications/[^/\s]+/federatedIdentityCredentials' },
            @{ Name = 'the tenant v2.0 issuer'; Pattern = '(?i)login\.microsoftonline\.com/[^/\s]+/v2\.0' },
            @{ Name = 'the host principal ID as the subject'; Pattern = '(?i)subject\s*=\s*\$hostPrincipalId' },
            @{ Name = 'the AzureADTokenExchange audience'; Pattern = 'api://AzureADTokenExchange' },
            @{ Name = 'a single-credential rollback'; Pattern = '(?i)--method\s+DELETE[\s\S]{0,400}federatedIdentityCredentials/' }
        )) {
            if ($runbookText -notmatch $requirement.Pattern) {
                $identityRunbookProblems.Add("the runbook does not document $($requirement.Name)")
            }
        }
    }
    else {
        $identityRunbookProblems.Add('the deployment runbook is missing')
    }

    $identityOwnershipValid = $identityOwnershipFindings.Count -eq 0 -and
        $publishesHostPrincipalId -and
        $identityRunbookProblems.Count -eq 0
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Agent 365 identity ownership' `
        -Status $(if ($identityOwnershipValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($identityOwnershipValid) { 'Infrastructure declares no Blueprint, agent identity, or federated identity credential, publishes the host principal ID, and the runbook documents the approved Graph credential step with its issuer, subject, audience, and single-credential rollback.' } else { 'Infrastructure declares an Agent 365 identity object, no longer publishes the host principal ID, or the runbook no longer documents the approved Graph credential step.' }) `
        -Remediation $(if ($identityOwnershipValid) { '' } else { 'Keep Blueprint, agent identity, and credential creation out of Bicep, keep the hostManagedIdentityPrincipalId output, and document the Graph federated identity credential step with its issuer, subject, audience, and rollback.' }) `
        -Data @{
            ForbiddenDeclarations    = @($identityOwnershipFindings)
            PublishesHostPrincipalId = [bool]$publishesHostPrincipalId
            RunbookProblems          = @($identityRunbookProblems | Sort-Object -Unique)
        }))

    # Azure Bot channels and OAuth. The bot must bind to the protected OBO route, carry Direct Line
    # v3, Teams, and the Aadv2 OBO connection in the bootstrap template, and never expose a secret.
    $botModulePath = 'infra\modules\azure-bot.bicep'
    $botProblems = [System.Collections.Generic.List[string]]::new()
    if (-not $fileContent.Contains($botModulePath)) {
        $botProblems.Add('the Azure Bot module is missing')
    }
    else {
        $botModule = $fileContent[$botModulePath]
        if ($botModule -notmatch "resource\s+\w+\s+'Microsoft\.BotService/botServices@") {
            $botProblems.Add('the module declares no Microsoft.BotService/botServices resource')
        }
        if ($botModule -notmatch "resource\s+\w+\s+'Microsoft\.BotService/botServices/channels@") {
            $botProblems.Add('the module declares no Direct Line channel resource')
        }
        if ($botModule -notmatch "channelName:\s*'DirectLineChannel'") {
            $botProblems.Add('the module declares no Direct Line channel')
        }
        if ($botModule -notmatch 'isV1Enabled:\s*false' -or $botModule -notmatch 'isV3Enabled:\s*true') {
            $botProblems.Add('Direct Line is not restricted to v3')
        }
        if ($botModule -notmatch "channelName:\s*'MsTeamsChannel'" -or
            $botModule -notmatch 'acceptedTerms:\s*true' -or
            $botModule -notmatch 'isEnabled:\s*true') {
            $botProblems.Add('the enabled Microsoft Teams channel is missing')
        }
        if ($botModule -notmatch 'isSecureSiteEnabled:\s*!empty\(directLineTrustedOrigins\)') {
            $botProblems.Add('Direct Line enhanced authentication is not tied to supplied trusted origins')
        }
        if ($botModule -notmatch "resource\s+\w+\s+'Microsoft\.BotService/botServices/connections@" -or
            $botModule -notmatch "serviceProviderId:\s*'30dd229c-58e3-4a48-bdfd-91ec48eb906c'" -or
            $botModule -notmatch "key:\s*'tenantId'" -or
            $botModule -notmatch "key:\s*'tokenExchangeUrl'" -or
            $botModule -notmatch "value:\s*'api://botid-\$\{oauthClientId\}'") {
            $botProblems.Add('the Aadv2 OBO OAuth connection is missing or incomplete')
        }
        if ($mainBicep -notmatch "oboMessagingEndpoint\s*=\s*'https://\$\{[^}]+\}/api/messages/obo'") {
            $botProblems.Add('the bot messaging endpoint is not bound to the protected OBO route')
        }
        if ($mainBicep -notmatch 'messagingEndpoint:\s*oboMessagingEndpoint') {
            $botProblems.Add('the bot module does not receive the protected OBO messaging endpoint')
        }
        if ($mainBicep -notmatch 'msaAppId:\s*oboChannelAppId') {
            $botProblems.Add('the bot is not bound to the OBO channel application parameter')
        }
        if ($mainBicep -notmatch 'deployTeamsChannel:\s*deployTeamsChannel' -or
            $mainBicep -notmatch 'deployDirectLineChannel:\s*deployDirectLineChannel' -or
            $mainBicep -notmatch 'deployOAuthConnection:\s*deployOboOAuthConnection' -or
            $mainBicep -notmatch 'oauthClientId:\s*oboChannelAppId' -or
            $mainBicep -notmatch 'oauthClientSecret:\s*oboChannelAppClientSecret' -or
            $mainBicep -notmatch 'oauthScopes:\s*oboOAuthScope') {
            $botProblems.Add('the complete OBO channel and OAuth configuration is not passed to the bot module')
        }
        if ($fileContent['infra\live-backend-container-apps-update.bicep'] -match "Microsoft\.BotService/") {
            $botProblems.Add('the existing-app update wrapper declares a bot resource')
        }
    }

    $moduleSecretIsSecure = $fileContent.Contains($botModulePath) -and
        $fileContent[$botModulePath] -match '(?s)@secure\(\)\s*@description\([^\r\n]*\)\s*param\s+oauthClientSecret\s+string'
    $mainSecretIsSecure = $mainBicep -match "(?s)@secure\(\)\s*@description\([^\r\n]*\)\s*param\s+oboChannelAppClientSecret\s+string\s*=\s*''"
    if (-not $moduleSecretIsSecure -or -not $mainSecretIsSecure) {
        $botProblems.Add('the OAuth client secret is not secure at both template boundaries')
    }
    if ($mainBicep -notmatch '!empty\(oboChannelAppClientSecret\)' -or
        $mainBicep -notmatch '!empty\(oboOAuthScope\)' -or
        $mainBicep -notmatch 'deployOboOAuthConnection') {
        $botProblems.Add('the Bot phase does not fail closed when OAuth inputs are absent')
    }
    $plaintextOAuthSecretFindings = @(
        foreach ($entry in $fileContent.GetEnumerator()) {
            if ($entry.Value -match "(?i)clientSecret:\s*'[^']+'") {
                [pscustomobject]@{ Path = $entry.Key; Reason = 'literal OAuth client secret' }
            }
        }
    )
    if ($plaintextOAuthSecretFindings.Count -gt 0) {
        $botProblems.Add('a template contains a literal OAuth client secret')
    }

    $channelSecretFindings = @(
        foreach ($entry in $fileContent.GetEnumerator()) {
            $declaresBotResource = $entry.Value -match '(?i)Microsoft\.BotService/'
            if ($entry.Value -match '(?i)listChannelWithKeys') {
                [pscustomobject]@{ Path = $entry.Key; Reason = 'channel key listing call' }
            }
            if ($declaresBotResource -and $entry.Value -match '(?i)listSecrets\(|\.listKeys\(') {
                [pscustomobject]@{ Path = $entry.Key; Reason = 'key listing call in a bot template' }
            }
            foreach ($match in [regex]::Matches($entry.Value, '(?m)^\s*output\s+(?<name>\w+)\s')) {
                if ($match.Groups['name'].Value -match '(?i)secret|password|token|key$|keys$') {
                    [pscustomobject]@{ Path = $entry.Key; Reason = "output $($match.Groups['name'].Value)" }
                }
            }
        }
    )
    if ($channelSecretFindings.Count -gt 0) {
        $botProblems.Add('a template reads or publishes a channel secret')
    }
    $directLineSiteBranded = $mainBicep -match "param directLineSiteName string = '[^']*(japan-expert|japanexpert)[^']*'"
    if (-not $directLineSiteBranded) {
        $botProblems.Add('the Direct Line site name default is not Japan Tourist Assistant branded')
    }

    $botBoundaryValid = $botProblems.Count -eq 0
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Azure Bot and Direct Line boundary' `
        -Status $(if ($botBoundaryValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($botBoundaryValid) { 'The bootstrap declares the Azure Bot, Direct Line v3, Teams, and Aadv2 OBO connection, binds them to the protected OBO route and channel application, and passes the OAuth credential only through secure parameters without output.' } else { 'The Bot, channel, or OAuth topology is missing, misbound, duplicated in the update wrapper, or exposes a secret.' }) `
        -Remediation $(if ($botBoundaryValid) { '' } else { 'Restore the complete bootstrap-only Bot topology, secure OAuth parameter propagation, protected OBO endpoint, and secret-free outputs.' }) `
        -Data @{
            Problems                     = @($botProblems | Sort-Object -Unique)
            SecretFindings               = @($channelSecretFindings)
            PlaintextOAuthSecretFindings = @($plaintextOAuthSecretFindings)
            ModuleSecretIsSecure         = [bool]$moduleSecretIsSecure
            MainSecretIsSecure           = [bool]$mainSecretIsSecure
        }))

    # Foundry protocol. gpt-5.6-sol is a Responses API deployment, so the host receives the project
    # endpoint and the deployment name. The host builds the documented /openai/v1 project base; the
    # Responses client owns the operation route and v1 uses implicit versioning.
    $hostBicepPath = 'infra\modules\agent-host-container-app.bicep'
    $hostSettings = Get-JexAgentHostRequiredSettings -RepositoryRoot $root
    $protocolProblems = [System.Collections.Generic.List[string]]::new()
    if (-not $hostSettings.Resolved) {
        $protocolProblems.Add('the agent host options contract could not be read')
    }
    elseif (-not $fileContent.Contains($hostBicepPath)) {
        $protocolProblems.Add('the agent host container module is missing')
    }
    else {
        $hostBicep = $fileContent[$hostBicepPath]
        foreach ($requiredSetting in @($hostSettings.RequiredSettings)) {
            if ($hostBicep -notmatch "name:\s*'$([regex]::Escape($requiredSetting))'") {
                $protocolProblems.Add("the deployment does not set the required host setting $requiredSetting")
            }
        }
        # Every host setting the deployment emits must exist in the options contract, so a retired or
        # invented key cannot reach a container even if it is spelled like a valid one.
        $emittedHostSettings = @([regex]::Matches(
            $hostBicep,
            "name:\s*'(?<name>$([regex]::Escape($hostSettings.SectionName))__\w+)'") |
            ForEach-Object { $_.Groups['name'].Value } | Sort-Object -Unique)
        foreach ($emitted in $emittedHostSettings) {
            if ($emitted -notin @($hostSettings.AllSettings)) {
                $protocolProblems.Add("the deployment sets $emitted, which the host options contract does not declare")
            }
        }
        $expectedProjectEndpoint = "https://\$\{foundryAccountName\}\.services\.ai\.azure\.com'"
        foreach ($templatePath in $entryTemplates) {
            if ($fileContent[$templatePath] -notmatch $expectedProjectEndpoint) {
                $protocolProblems.Add("$templatePath does not derive the Foundry OpenAI-compatible endpoint from the pinned account name")
            }
        }
    }
    $retiredProtocolFindings = @(
        foreach ($entry in $fileContent.GetEnumerator()) {
            # Strip Bicep comments so the rule matches deployed configuration, not the documentation
            # that explains the rule.
            $scanText = if ($entry.Key -like '*.bicep') {
                [regex]::Replace($entry.Value, '(?s:/\*.*?\*/)|(?m://.*$)', '')
            }
            else {
                $entry.Value
            }
            foreach ($pattern in @(
                @{ Rule = 'account-root Azure OpenAI host setting'; Pattern = 'AgentHost__AzureOpenAI' },
                @{ Rule = 'raw responses route'; Pattern = '(?i)/openai/responses' },
                @{ Rule = 'pinned api-version'; Pattern = '(?i)api-version' }
            )) {
                if ($scanText -match $pattern.Pattern) {
                    [pscustomobject]@{ Path = $entry.Key; Rule = $pattern.Rule }
                }
            }
        }
        # Deployment documentation this project owns is checked for a resurrected configuration key
        # only. Prose about the forbidden route and version is how the rule is explained. Historical
        # M0-M7 records intentionally keep the retired names and are out of scope.
        foreach ($ownedDoc in @('infra\README.md', 'tools\README.md')) {
            $ownedDocPath = Join-Path $root $ownedDoc
            if ((Test-Path -LiteralPath $ownedDocPath -PathType Leaf) -and
                (Get-Content -LiteralPath $ownedDocPath -Raw) -match 'AgentHost__AzureOpenAI') {
                [pscustomobject]@{ Path = $ownedDoc; Rule = 'account-root Azure OpenAI host setting' }
            }
        }
    )
    if ($retiredProtocolFindings.Count -gt 0) {
        $protocolProblems.Add('a template injects a retired endpoint setting, a raw responses route, or an api-version')
    }

    $protocolValid = $protocolProblems.Count -eq 0
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Foundry Responses protocol boundary' `
        -Status $(if ($protocolValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($protocolValid) { "The deployment sets every required host setting ($($hostSettings.RequiredSettings -join ', ')), derives the project endpoint from the pinned account and project, and injects no raw responses route or api-version." } else { 'The deployed host configuration does not match the agent host options contract, or a template injects a retired endpoint setting, raw responses route, or api-version.' }) `
        -Remediation $(if ($protocolValid) { '' } else { 'Set exactly the required AgentHost settings, derive the project endpoint from the pinned names, and leave the /responses operation and implicit versioning to the Responses client.' }) `
        -Data @{
            SectionName      = $hostSettings.SectionName
            RequiredSettings = @($hostSettings.RequiredSettings)
            Problems         = @($protocolProblems | Sort-Object -Unique)
            RetiredFindings  = @($retiredProtocolFindings)
        }))

    # Foundry runtime access. Keyless Responses inference is authorized by the child identity's token
    # for the ai.azure.com resource, so the deployed token scope must match the host contract and the
    # documented data-plane role must stay a child-only, account-scoped, out-of-template grant.
    $foundryAccess = Get-JexFoundryRuntimeAccessPolicy -RepositoryRoot $root
    $accessProblems = [System.Collections.Generic.List[string]]::new()
    if (-not $foundryAccess.Resolved) {
        $accessProblems.Add('the host Foundry token scope could not be read from source')
    }
    elseif ($fileContent.Contains($hostBicepPath)) {
        $hostBicepContent = $fileContent[$hostBicepPath]
        if ($hostBicepContent -notmatch "param foundryTokenScope string = '$([regex]::Escape($foundryAccess.TokenScope))'") {
            $accessProblems.Add("the deployed agentic-foundry token scope does not match the host contract scope $($foundryAccess.TokenScope)")
        }
        if ($hostBicepContent -notmatch "Handlers__agentic-foundry__Settings__Scopes__0'\s*value:\s*foundryTokenScope") {
            $accessProblems.Add('the agentic-foundry handler scope is not bound to the token scope parameter')
        }
    }

    $foundryRoleFindings = @(
        foreach ($entry in $fileContent.GetEnumerator()) {
            foreach ($retiredRole in @('Cognitive Services OpenAI User', 'Foundry User', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')) {
                if ($entry.Value -match "(?i)$([regex]::Escape($retiredRole))") {
                    [pscustomobject]@{ Path = $entry.Key; Role = $retiredRole }
                }
            }
        }
    )
    if ($foundryRoleFindings.Count -gt 0) {
        $accessProblems.Add('a deployment template still references a retired Foundry data-plane role')
    }
    $runbookPath = Join-Path $root 'infra\README.md'
    if (Test-Path -LiteralPath $runbookPath -PathType Leaf) {
        $runbook = Get-Content -LiteralPath $runbookPath -Raw
        if ($runbook -notmatch "--role\s+'$([regex]::Escape($foundryAccess.RoleName))'") {
            $accessProblems.Add("the runbook does not grant $($foundryAccess.RoleName)")
        }
        if ($runbook -notmatch '(?i)accounts/a365-ai-foundry') {
            $accessProblems.Add('the runbook does not scope the grant to the existing Foundry account')
        }
        if ($runbook -notmatch '(?i)not.{0,40}host (user-assigned managed identity|UAMI)') {
            $accessProblems.Add('the runbook does not exclude the host managed identity from the grant')
        }
    }
    else {
        $accessProblems.Add('the deployment runbook is missing')
    }

    $accessValid = $accessProblems.Count -eq 0
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Foundry runtime access boundary' `
        -Status $(if ($accessValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($accessValid) { "The deployed inference token scope is $($foundryAccess.TokenScope) and the documented grant is $($foundryAccess.RoleName) at the existing Foundry account scope for child identities only." } else { 'The deployed token scope, the documented Foundry role, or the child-only grant boundary does not match the keyless Responses contract.' }) `
        -Remediation $(if ($accessValid) { '' } else { 'Keep the deployed agentic-foundry scope equal to the host contract scope, document Cognitive Services User at the Foundry account scope for child identities only, and remove retired role references.' }) `
        -Data @{
            TokenScope        = $foundryAccess.TokenScope
            RoleName          = $foundryAccess.RoleName
            Problems          = @($accessProblems | Sort-Object -Unique)
            RetiredRoleClaims = @($foundryRoleFindings)
        }))

    @($results)
}

function Get-JexFoundryRuntimeAccessPolicy {
    <#
        .SYNOPSIS
        Returns the Foundry inference token scope declared by the host and the documented built-in role.

        .DESCRIPTION
        The token scope is read from the host source so deployment configuration cannot drift from the
        resource the runtime actually requests. The role name is the Microsoft-documented built-in
        role for keyless Responses inference at the Foundry account scope.
    #>
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $layout = Get-JexSourceLayout -RepositoryRoot $root
    $scope = ''
    $tokenContextPath = if ([string]::IsNullOrWhiteSpace($layout.HostDirectory)) {
        ''
    }
    else {
        Join-Path $layout.HostDirectory 'AgentIdentityTokenContext.cs'
    }
    if ($tokenContextPath -and (Test-Path -LiteralPath $tokenContextPath -PathType Leaf)) {
        $match = [regex]::Match(
            (Get-Content -LiteralPath $tokenContextPath -Raw),
            'Foundry\s*=\s*"(?<scope>https://[^"]+)"')
        if ($match.Success) {
            $scope = $match.Groups['scope'].Value
        }
    }

    [pscustomobject]@{
        Resolved   = -not [string]::IsNullOrWhiteSpace($scope)
        TokenScope = $scope
        RoleName   = 'Cognitive Services User'
    }
}

function Get-JexMcpProviderSection {
    <#
        .SYNOPSIS
        Returns the provider configuration sections each MCP service actually binds.

        .DESCRIPTION
        Section names are read from the MCP service's own appsettings.json instead of being
        hard-coded, so a data-source change by the MCP owner surfaces here as an explicit failure
        with the exact missing section rather than as silent deployment drift.
    #>
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $layout = Get-JexSourceLayout -RepositoryRoot $root
    $infrastructureSections = @('McpAuthorization', 'Logging', 'AllowedHosts', 'Kestrel', 'Urls')
    $services = [ordered]@{}

    foreach ($service in @('attractions', 'weather', 'accommodation', 'currency')) {
        $projectPath = $layout.McpServiceProjects[$service]
        $settingsPath = if ([string]::IsNullOrWhiteSpace($projectPath)) {
            ''
        }
        else {
            Join-Path (Split-Path -Parent $projectPath) 'appsettings.json'
        }
        $sections = @()
        $resolved = $false
        if ($settingsPath -and (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
            try {
                $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -Depth 20
                $sections = @($settings.PSObject.Properties.Name | Where-Object {
                    $_ -notin $infrastructureSections
                } | Sort-Object)
                $resolved = $true
            }
            catch {
                $sections = @()
            }
        }
        $services[$service] = [pscustomobject][ordered]@{
            Service          = $service
            SettingsPath     = if ($settingsPath) { [IO.Path]::GetRelativePath($root, $settingsPath) } else { '' }
            Resolved         = $resolved
            ProviderSections = @($sections)
        }
    }

    $services
}

function Get-JexProviderSettingDefault {
    <#
        .SYNOPSIS
        Resolves a compiled provider setting value that is a literal or a single parameter reference.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Parameters
    )

    if ($Value -isnot [string]) {
        return [pscustomobject]@{ Resolved = $true; Value = [string]$Value }
    }

    $match = [regex]::Match($Value, "^\[(?:string\()?parameters\('(?<name>\w+)'\)\)?\]$")
    if (-not $match.Success) {
        if ($Value.StartsWith('[', [StringComparison]::Ordinal)) {
            return [pscustomobject]@{ Resolved = $false; Value = '' }
        }
        return [pscustomobject]@{ Resolved = $true; Value = $Value }
    }

    $parameterName = $match.Groups['name'].Value
    if ($null -eq $Parameters -or $null -eq $Parameters.PSObject.Properties[$parameterName]) {
        return [pscustomobject]@{ Resolved = $false; Value = '' }
    }
    $default = $Parameters.$parameterName.PSObject.Properties['defaultValue']
    if ($null -eq $default) {
        return [pscustomobject]@{ Resolved = $false; Value = '' }
    }
    [pscustomobject]@{ Resolved = $true; Value = [string]$default.Value }
}

function Test-JexMcpProviderConfiguration {
    <#
        .SYNOPSIS
        Validates the non-secret MCP provider configuration carried by the deployment templates.
    #>
    [CmdletBinding()]
    param(
        [string] $RepositoryRoot = $script:DefaultRepositoryRoot,

        [AllowNull()]
        [object] $FileContent = $null
    )

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $results = [System.Collections.Generic.List[object]]::new()
    $bootstrapPath = 'infra\main.bicep'
    $updatePath = 'infra\live-backend-container-apps-update.bicep'
    $compiledPath = 'infra\live-backend-container-apps-update.json'

    if ($null -eq $FileContent) {
        $FileContent = [ordered]@{}
        foreach ($relativePath in @($bootstrapPath, $updatePath, $compiledPath)) {
            $fullPath = Join-Path $root $relativePath
            if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
                $FileContent[$relativePath] = (Get-Content -LiteralPath $fullPath -Raw)
            }
        }
    }

    $serviceParameters = [ordered]@{
        attractions   = 'attractionsProviderSettings'
        weather       = 'weatherProviderSettings'
        accommodation = 'accommodationProviderSettings'
        currency      = 'currencyProviderSettings'
    }
    $retiredSettingPrefixes = @(
        'AzureMaps__', 'Kto__', 'KtoTourApi__', 'KoreaEximbank__', 'ForexRateApi__',
        'OpenWeather__', 'OpenMeteo__'
    )

    $compiledParameters = $null
    if ($FileContent.Contains($compiledPath)) {
        try {
            $compiledTemplate = $FileContent[$compiledPath] | ConvertFrom-Json -Depth 40
            $compiledParameters = $compiledTemplate.parameters
        }
        catch {
            $compiledParameters = $null
        }
    }

    if ($null -eq $compiledParameters) {
        $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'MCP provider configuration' -Status 'Fail' `
            -Message 'The compiled update template could not be read, so deployed provider configuration cannot be validated.' `
            -Remediation 'Recompile infra/live-backend-container-apps-update.bicep to its checked-in JSON.'))
        return @($results)
    }

    $expectedSections = Get-JexMcpProviderSection -RepositoryRoot $root
    $settingFindings = [System.Collections.Generic.List[object]]::new()
    $problems = [System.Collections.Generic.List[string]]::new()

    foreach ($entry in $serviceParameters.GetEnumerator()) {
        $service = $entry.Key
        $parameterName = $entry.Value
        $serviceSections = $expectedSections[$service]
        if (-not $serviceSections.Resolved) {
            $problems.Add("$service MCP appsettings.json could not be read")
            continue
        }

        $declared = $compiledParameters.PSObject.Properties[$parameterName]
        if ($null -eq $declared -or $null -eq $declared.Value.PSObject.Properties['defaultValue']) {
            $problems.Add("$parameterName has no default in the compiled template")
            continue
        }

        $settings = @($declared.Value.defaultValue)
        $observedSections = [System.Collections.Generic.List[string]]::new()
        foreach ($setting in $settings) {
            $settingName = [string]$setting.name
            $resolvedValue = Get-JexProviderSettingDefault -Value $setting.value -Parameters $compiledParameters
            $sectionName = @($settingName -split '__')[0]
            if (-not $observedSections.Contains($sectionName)) {
                $observedSections.Add($sectionName)
            }

            $isUrl = $resolvedValue.Value -match '^[a-z][a-z0-9+.-]*://'
            $isSecureUrl = $resolvedValue.Value -match '^https://'
            $requiresTrailingSlash = $settingName -match 'BaseAddress$'
            $isUserAgent = $settingName -match 'UserAgent$'
            $finding = [pscustomobject][ordered]@{
                Service          = $service
                Setting          = $settingName
                Section          = $sectionName
                Resolved         = $resolvedValue.Resolved
                IsUrl            = $isUrl
                SecureUrl        = (-not $isUrl) -or $isSecureUrl
                TrailingSlash    = (-not $requiresTrailingSlash) -or $resolvedValue.Value.EndsWith('/')
                ContactReference = (-not $isUserAgent) -or (
                    $resolvedValue.Value.Length -ge 16 -and
                    $resolvedValue.Value.Contains('+http', [StringComparison]::OrdinalIgnoreCase))
                CommitSafeAgent  = (-not $isUserAgent) -or (
                    -not $resolvedValue.Value.Contains('@', [StringComparison]::Ordinal) -and
                    -not $resolvedValue.Value.Contains('mailto:', [StringComparison]::OrdinalIgnoreCase))
                Retired          = @($retiredSettingPrefixes | Where-Object {
                    $settingName.StartsWith($_, [StringComparison]::OrdinalIgnoreCase)
                }).Count -gt 0
            }
            $settingFindings.Add($finding)

            if (-not $finding.Resolved) { $problems.Add("$service/$settingName default could not be resolved") }
            if (-not $finding.SecureUrl) { $problems.Add("$service/$settingName is not an HTTPS endpoint") }
            if (-not $finding.TrailingSlash) { $problems.Add("$service/$settingName must end with a slash") }
            if (-not $finding.ContactReference) { $problems.Add("$service/$settingName needs a +URL contact reference") }
            if (-not $finding.CommitSafeAgent) { $problems.Add("$service/$settingName must not commit a mailbox address") }
            if ($finding.Retired) { $problems.Add("$service/$settingName is a retired provider setting") }
            if ($settingName -notmatch '^[A-Za-z0-9]+__[A-Za-z0-9_]+$') {
                $problems.Add("$service/$settingName is not a section-scoped configuration key")
            }
        }

        foreach ($requiredSection in @($serviceSections.ProviderSections)) {
            if ($requiredSection -notin $observedSections) {
                $problems.Add("$service deployment is missing configuration for the $requiredSection section")
            }
        }
        foreach ($observedSection in $observedSections) {
            if ($observedSection -notin @($serviceSections.ProviderSections)) {
                $problems.Add("$service deployment configures unknown section $observedSection")
            }
        }
    }

    $providerConfigurationValid = $problems.Count -eq 0 -and $settingFindings.Count -gt 0
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'MCP provider configuration' `
        -Status $(if ($providerConfigurationValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($providerConfigurationValid) { "All $($settingFindings.Count) deployed provider settings are credential-free HTTPS configuration matching the sections each MCP service binds." } else { 'Deployed provider configuration does not match the sections the MCP services bind, or a setting fails its non-secret HTTPS and contact-reference rules.' }) `
        -Remediation $(if ($providerConfigurationValid) { '' } else { 'Align the provider settings parameters in both deployment templates with the MCP service appsettings sections, using HTTPS endpoints and a commit-safe User-Agent.' }) `
        -Data @{
            ExpectedSections = @($expectedSections.Values)
            Settings         = @($settingFindings)
            Problems         = @($problems | Sort-Object -Unique)
        }))

    $parityProblems = [System.Collections.Generic.List[string]]::new()
    if ($FileContent.Contains($bootstrapPath) -and $FileContent.Contains($updatePath)) {
        foreach ($parameterName in $serviceParameters.Values) {
            $pattern = "(?s)param\s+$([regex]::Escape($parameterName))\s+ContainerAppSetting\[\]\s*=\s*\[(?<body>.*?)\r?\n\]"
            $bootstrapMatch = [regex]::Match($FileContent[$bootstrapPath], $pattern)
            $updateMatch = [regex]::Match($FileContent[$updatePath], $pattern)
            if (-not $bootstrapMatch.Success -or -not $updateMatch.Success) {
                $parityProblems.Add("$parameterName is not declared in both templates")
                continue
            }
            $bootstrapBody = ($bootstrapMatch.Groups['body'].Value -replace '\s+', ' ').Trim()
            $updateBody = ($updateMatch.Groups['body'].Value -replace '\s+', ' ').Trim()
            if ($bootstrapBody -ne $updateBody) {
                $parityProblems.Add("$parameterName defaults differ between the bootstrap and update templates")
            }
        }
    }
    else {
        $parityProblems.Add('A deployment template is missing')
    }

    $parityValid = $parityProblems.Count -eq 0
    $results.Add((New-JexValidationResult -Area 'Deployment' -Check 'Provider configuration parity' `
        -Status $(if ($parityValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($parityValid) { 'The bootstrap and update templates declare identical provider configuration defaults.' } else { 'Provider configuration defaults differ between the bootstrap and update templates.' }) `
        -Remediation $(if ($parityValid) { '' } else { 'Keep the provider settings defaults identical so an update or rollback never re-points a data source.' }) `
        -Data @{ Problems = @($parityProblems | Sort-Object -Unique) }))

    @($results)
}

function Get-JexDeploymentPolicy {
    <#
        .SYNOPSIS
        Returns the approved deployment targets and confirms the milestone manifest still states them.
    #>
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $approvedResourceGroup = 'a365-custom-agents'
    $foundryResourceGroup = 'rg-ai-foundry'
    $foundryAccountName = 'a365-ai-foundry'
    $foundryProjectName = 'default'
    $modelDeploymentName = 'gpt-5.6-sol'
    $resourceBaseName = 'japanexpert'

    $milestoneId = ''
    $manifestText = ''
    try {
        $milestone = Get-JexMilestoneState -RepositoryRoot $root
        $milestoneId = $milestone.Current.id
        $manifestText = ($milestone.Current | ConvertTo-Json -Depth 20)
    }
    catch {
        $manifestText = ''
    }

    $requiredManifestValues = @($approvedResourceGroup, $foundryAccountName, $modelDeploymentName)
    $missingManifestValues = @($requiredManifestValues | Where-Object {
        -not $manifestText.Contains($_, [StringComparison]::OrdinalIgnoreCase)
    })

    [pscustomobject][ordered]@{
        MilestoneId           = $milestoneId
        ApprovedResourceGroup = $approvedResourceGroup
        FoundryResourceGroup  = $foundryResourceGroup
        FoundryAccountName    = $foundryAccountName
        FoundryProjectName    = $foundryProjectName
        ModelDeploymentName   = $modelDeploymentName
        ResourceBaseName      = $resourceBaseName
        MissingManifestValues = @($missingManifestValues)
        IsConsistent          = $missingManifestValues.Count -eq 0
    }
}

function Get-JexExpectedDeploymentNames {
    <#
        .SYNOPSIS
        Returns the deterministic resource name parameters, their defaults, and Azure length limits.
    #>
    [CmdletBinding()]
    param([string] $ResourceBaseName = 'japanexpert')

    $definitions = @(
        @{ Parameter = 'logAnalyticsWorkspaceName'; Template = 'log-{0}'; MaximumLength = 63; UpdateTemplate = $false },
        @{ Parameter = 'applicationInsightsName'; Template = 'appi-{0}'; MaximumLength = 255; UpdateTemplate = $true },
        @{ Parameter = 'containerRegistryName'; Template = 'cr{0}'; MaximumLength = 50; UpdateTemplate = $true },
        @{ Parameter = 'containerAppEnvironmentName'; Template = 'cae-{0}'; MaximumLength = 60; UpdateTemplate = $true },
        @{ Parameter = 'hostIdentityName'; Template = 'id-agent-{0}'; MaximumLength = 128; UpdateTemplate = $true },
        @{ Parameter = 'attractionsIdentityName'; Template = 'id-attract-{0}'; MaximumLength = 128; UpdateTemplate = $true },
        @{ Parameter = 'weatherIdentityName'; Template = 'id-weather-{0}'; MaximumLength = 128; UpdateTemplate = $true },
        @{ Parameter = 'accommodationIdentityName'; Template = 'id-stay-{0}'; MaximumLength = 128; UpdateTemplate = $true },
        @{ Parameter = 'currencyIdentityName'; Template = 'id-fx-{0}'; MaximumLength = 128; UpdateTemplate = $true },
        @{ Parameter = 'hostAppName'; Template = 'ca-agent-{0}'; MaximumLength = 32; UpdateTemplate = $true },
        @{ Parameter = 'attractionsAppName'; Template = 'ca-attract-{0}'; MaximumLength = 32; UpdateTemplate = $true },
        @{ Parameter = 'weatherAppName'; Template = 'ca-weather-{0}'; MaximumLength = 32; UpdateTemplate = $true },
        @{ Parameter = 'accommodationAppName'; Template = 'ca-stay-{0}'; MaximumLength = 32; UpdateTemplate = $true },
        @{ Parameter = 'currencyAppName'; Template = 'ca-fx-{0}'; MaximumLength = 32; UpdateTemplate = $true },
        @{ Parameter = 'mcpApiApplicationName'; Template = 'api-{0}'; MaximumLength = 120; UpdateTemplate = $false },
        @{ Parameter = 'azureBotName'; Template = 'bot-{0}'; MaximumLength = 64; UpdateTemplate = $false }
    )

    @($definitions | ForEach-Object {
        [pscustomobject][ordered]@{
            Parameter      = $_.Parameter
            Default        = ($_.Template -f '${resourceBaseName}')
            ResolvedName   = ($_.Template -f $ResourceBaseName)
            MaximumLength  = $_.MaximumLength
            UpdateTemplate = $_.UpdateTemplate
        }
    })
}

function Get-JexAgentHostRequiredSettings {
    <#
        .SYNOPSIS
        Returns the configuration keys the agent host declares as required.

        .DESCRIPTION
        The host options class is the contract. Required property names are read from it and mapped to
        their double-underscore environment keys, so a host configuration rename surfaces here as an
        explicit failure naming the missing key instead of as silent deployment drift.
    #>
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $layout = Get-JexSourceLayout -RepositoryRoot $root
    $optionsPath = if ([string]::IsNullOrWhiteSpace($layout.HostDirectory)) {
        ''
    }
    else {
        Join-Path $layout.HostDirectory 'AgentHostOptions.cs'
    }

    if (-not $optionsPath -or -not (Test-Path -LiteralPath $optionsPath -PathType Leaf)) {
        return [pscustomobject]@{ Resolved = $false; SectionName = ''; RequiredSettings = @() }
    }

    $content = Get-Content -LiteralPath $optionsPath -Raw
    $sectionMatch = [regex]::Match($content, 'SectionName\s*=\s*"(?<section>\w+)"')
    $section = if ($sectionMatch.Success) { $sectionMatch.Groups['section'].Value } else { '' }
    $required = @([regex]::Matches(
        $content,
        '(?s)\[Required\][^\]]*?public\s+\w+\??\s+(?<name>\w+)\s*\{') | ForEach-Object { $_.Groups['name'].Value })
    $all = @([regex]::Matches(
        $content,
        '(?m)^\s*public\s+(?!const\b)[\w<>\?\[\]]+\s+(?<name>\w+)\s*\{\s*get') | ForEach-Object { $_.Groups['name'].Value })

    [pscustomobject]@{
        Resolved         = (-not [string]::IsNullOrWhiteSpace($section)) -and $required.Count -gt 0
        SectionName      = $section
        RequiredSettings = @($required | ForEach-Object { "${section}__$_" })
        AllSettings      = @($all | Sort-Object -Unique | ForEach-Object { "${section}__$_" })
    }
}

function Test-JexAzureReadiness {
    [CmdletBinding()]
    param(
        [string] $RepositoryRoot = $script:DefaultRepositoryRoot,

        [switch] $Online,

        [string] $SubscriptionId = '',

        [string[]] $ResourceId = @()
    )

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $results = [System.Collections.Generic.List[object]]::new()
    $milestone = Get-JexMilestoneState -RepositoryRoot $root
    $azCommand = Get-Command az -ErrorAction SilentlyContinue
    if ($null -eq $azCommand) {
        return ,(New-JexValidationResult -Area 'Azure' -Check 'Azure CLI' -Status 'Fail' `
            -Message 'Azure CLI is not installed or is not on PATH.' `
            -Remediation 'Install Azure CLI before running Azure readiness checks.')
    }

    $results.Add((New-JexValidationResult -Area 'Azure' -Check 'Azure CLI' -Status 'Pass' `
        -Message 'Azure CLI is available.' -Data @{ Command = $azCommand.Source }))

    $endpoint = [Environment]::GetEnvironmentVariable('AgentHost__FoundryProjectEndpoint', 'Process')
    $deployment = [Environment]::GetEnvironmentVariable('AgentHost__FoundryModelDeployment', 'Process')

    if ([string]::IsNullOrWhiteSpace($endpoint)) {
        $results.Add((New-JexValidationResult -Area 'Azure' -Check 'Foundry project endpoint' -Status 'Skip' `
            -Message 'AgentHost__FoundryProjectEndpoint is not set in this process.' `
            -Remediation 'Set it only when validating a configured local environment.'))
    }
    else {
        $endpointUri = $null
        $validEndpoint = [Uri]::TryCreate($endpoint, [UriKind]::Absolute, [ref]$endpointUri) -and
            $endpointUri.Scheme -eq 'https'
        $results.Add((New-JexValidationResult -Area 'Azure' -Check 'Foundry project endpoint' `
            -Status $(if ($validEndpoint) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($validEndpoint) { 'Configured endpoint is an absolute HTTPS URI.' } else { 'Configured endpoint is not an absolute HTTPS URI.' }) `
            -Remediation $(if ($validEndpoint) { '' } else { 'Set AgentHost__FoundryProjectEndpoint to the Foundry project HTTPS endpoint.' })))
    }

    $results.Add((New-JexValidationResult -Area 'Azure' -Check 'Foundry model deployment' `
        -Status $(if ([string]::IsNullOrWhiteSpace($deployment)) { 'Skip' } else { 'Pass' }) `
        -Message $(if ([string]::IsNullOrWhiteSpace($deployment)) { 'AgentHost__FoundryModelDeployment is not set in this process.' } else { 'A deployment name is configured.' }) `
        -Remediation $(if ([string]::IsNullOrWhiteSpace($deployment)) { 'Set it only when validating a configured local environment.' } else { '' })))

    if (-not $Online) {
        if (-not [string]::IsNullOrWhiteSpace($SubscriptionId) -or @($ResourceId).Count -gt 0) {
            $results.Add((New-JexValidationResult -Area 'Azure' -Check 'Online switch' -Status 'Fail' `
                -Message 'SubscriptionId and ResourceId checks require -Online.' `
                -Remediation 'Add -Online only when Azure subscription reads are intended.'))
        }
        $results.Add((New-JexValidationResult -Area 'Azure' -Check 'Azure account' -Status 'Skip' `
            -Message 'Online Azure checks were not requested. No Azure API call was made.'))
        return @($results)
    }

    if (-not $milestone.Current.allowsTenantReads) {
        $results.Add((New-JexValidationResult -Area 'Azure' -Check 'Milestone tenant-read authorization' -Status 'Fail' `
            -Message "Milestone '$($milestone.Current.id)' does not allow tenant reads." `
            -Remediation 'Do not run online validation until a reviewed milestone explicitly allows tenant reads.'))
        return @($results)
    }

    $accountInvocation = Invoke-JexNativeCommand -FilePath 'az' -ArgumentList @(
        'account', 'show', '--only-show-errors', '--output', 'json'
    ) -WorkingDirectory $root
    if ($accountInvocation.ExitCode -ne 0) {
        $results.Add((New-JexValidationResult -Area 'Azure' -Check 'Azure account' -Status 'Fail' `
            -Message 'Azure CLI does not have a usable signed-in account.' `
            -Remediation 'Run az login yourself, select the intended tenant/subscription, and retry.' `
            -Data @{ ExitCode = $accountInvocation.ExitCode; Output = $accountInvocation.Output }))
        return @($results)
    }

    try {
        $account = $accountInvocation.Output | ConvertFrom-Json -Depth 10
        $subscriptionMatches = [string]::IsNullOrWhiteSpace($SubscriptionId) -or
            $account.id -eq $SubscriptionId
        $results.Add((New-JexValidationResult -Area 'Azure' -Check 'Azure account' `
            -Status $(if ($subscriptionMatches) { 'Pass' } else { 'Fail' }) `
            -Message "Signed in to tenant '$($account.tenantId)' and subscription '$($account.id)'." `
            -Remediation $(if ($subscriptionMatches) { '' } else { 'Select the subscription requested by the validation command.' }) `
            -Data @{ SubscriptionId = $account.id; TenantId = $account.tenantId; Name = $account.name }))
    }
    catch {
        $results.Add((New-JexValidationResult -Area 'Azure' -Check 'Azure account response' -Status 'Fail' `
            -Message 'Azure CLI account output was not valid JSON.' -Remediation $_.Exception.Message))
    }

    foreach ($id in @($ResourceId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $resourceInvocation = Invoke-JexNativeCommand -FilePath 'az' -ArgumentList @(
            'resource', 'show', '--ids', $id, '--only-show-errors', '--output', 'json'
        ) -WorkingDirectory $root
        $results.Add((New-JexValidationResult -Area 'Azure' -Check "Resource: $id" `
            -Status $(if ($resourceInvocation.ExitCode -eq 0) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($resourceInvocation.ExitCode -eq 0) { 'Resource is visible to the current Azure identity.' } else { 'Resource could not be read.' }) `
            -Remediation $(if ($resourceInvocation.ExitCode -eq 0) { '' } else { 'Verify the resource ID, tenant, subscription, and read access.' }) `
            -Data @{ ExitCode = $resourceInvocation.ExitCode }))
    }

    @($results)
}

function Test-JexPurviewMiddlewareOrder {
    [CmdletBinding()]
    param([AllowEmptyString()][string] $Source)

    $withoutComments = [regex]::Replace($Source, '(?s:/\*.*?\*/)|(?m://.*$)', '')
    $withoutComments -match '(?s)\.WithPurview\s*\(.*?\.UseFunctionInvocation\s*\(.*?\.UseOpenTelemetry\s*\('
}

function Get-JexPurviewEnforcementResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int] $StatusCode,

        [AllowEmptyString()]
        [string] $Content = '',

        [switch] $ExpectBlock
    )

    if ($StatusCode -notin @(200, 202, 204)) {
        return New-JexValidationResult -Area 'Purview' -Check 'processContent enforcement' -Status 'Fail' `
            -Message "HTTP $StatusCode is not a successful processContent response." `
            -Remediation 'Resolve connectivity and authorization before evaluating enforcement.' `
            -Data @{ StatusCode = $StatusCode; EnforcementEvidence = $false }
    }

    if ([string]::IsNullOrWhiteSpace($Content)) {
        if ($StatusCode -eq 200) {
            return New-JexValidationResult -Area 'Purview' -Check 'processContent enforcement' -Status 'Fail' `
                -Message 'HTTP 200 returned no response body, so no enforcement evidence is available.' `
                -Remediation 'Capture the client request ID and investigate why a completed evaluation omitted its response.' `
                -Data @{ StatusCode = $StatusCode; EnforcementEvidence = $false }
        }

        return New-JexValidationResult -Area 'Purview' -Check 'processContent enforcement' `
            -Status $(if ($ExpectBlock) { 'Fail' } else { 'Skip' }) `
            -Message "HTTP $StatusCode confirms acceptance but provides no synchronous enforcement evidence." `
            -Remediation $(if ($ExpectBlock) { 'Use a completed 200 response or tenant-side evidence before claiming blocking enforcement.' } else { '' }) `
            -Data @{ StatusCode = $StatusCode; EnforcementEvidence = $false }
    }

    try {
        $response = $Content | ConvertFrom-Json -Depth 30
    }
    catch {
        return New-JexValidationResult -Area 'Purview' -Check 'processContent enforcement' -Status 'Fail' `
            -Message 'Purview returned a non-empty response that was not valid JSON.' `
            -Remediation 'Capture the client request ID and investigate the Graph response format.' `
            -Data @{ StatusCode = $StatusCode; EnforcementEvidence = $false; Error = $_.Exception.Message }
    }

    $responseProperties = @($response.PSObject.Properties.Name)
    $processingErrors = [System.Collections.Generic.List[object]]::new()
    if ($responseProperties -contains 'processingErrors') {
        foreach ($processingError in @($response.processingErrors)) {
            if ($null -ne $processingError) {
                $processingErrors.Add($processingError)
            }
        }
    }
    $policyActions = [System.Collections.Generic.List[object]]::new()
    if ($responseProperties -contains 'policyActions') {
        foreach ($policyAction in @($response.policyActions)) {
            if ($null -ne $policyAction) {
                $policyActions.Add($policyAction)
            }
        }
    }
    $blocked = @($policyActions | Where-Object {
        $_.PSObject.Properties.Name -contains 'restrictionAction' -and
            $_.restrictionAction -eq 'block'
    }).Count -gt 0
    $expectationMet = $processingErrors.Count -eq 0 -and (-not $ExpectBlock -or $blocked)
    New-JexValidationResult -Area 'Purview' -Check 'processContent enforcement' `
        -Status $(if ($expectationMet) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($processingErrors.Count -gt 0) { 'Purview returned processing errors.' } elseif ($blocked) { 'Purview returned a block action for the synthetic probe.' } else { 'Purview returned a completed policy evaluation without a block action.' }) `
        -Remediation $(if ($expectationMet) { '' } else { 'Review processing errors and DLP policy scope before enabling the agent.' }) `
        -Data @{
            StatusCode           = $StatusCode
            PolicyActionCount    = $policyActions.Count
            ProcessingErrorCount = $processingErrors.Count
            Blocked              = $blocked
            ProtectionScopeState = if ($responseProperties -contains 'protectionScopeState') { $response.protectionScopeState } else { $null }
            EnforcementEvidence  = $true
        }
}

function Test-JexPurviewReadiness {
    [CmdletBinding()]
    param(
        [string] $RepositoryRoot = $script:DefaultRepositoryRoot,

        [switch] $RequireImplemented,

        [switch] $Online,

        [switch] $CheckTenantPolicy,

        [switch] $ProbePolicy,

        [string] $UserId = '',

        [string] $ApplicationId = '',

        [string] $BlueprintId = '',

        [string] $AgentInstanceId = '',

        [string] $AccessTokenEnvironmentVariable = 'PURVIEW_GRAPH_ACCESS_TOKEN',

        [string] $ProbeText = 'Japan Tourist Assistant synthetic Purview validation probe.',

        [switch] $ExpectBlock,

        [ValidateRange(1, 120)]
        [int] $ProbeTimeoutSeconds = 30
    )

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $milestone = Get-JexMilestoneState -RepositoryRoot $root
    $results = [System.Collections.Generic.List[object]]::new()
    $purviewVersion = Get-JexPackageVersion -PackageName 'Microsoft.Agents.AI.Purview' -RepositoryRoot $root
    $agentFrameworkVersion = Get-JexPackageVersion -PackageName 'Microsoft.Agents.AI' -RepositoryRoot $root
    $azureIdentityVersion = Get-JexPackageVersion -PackageName 'Azure.Identity' -RepositoryRoot $root
    $extensionsAiVersion = Get-JexPackageVersion -PackageName 'Microsoft.Extensions.AI' -RepositoryRoot $root
    $isImplemented = -not [string]::IsNullOrWhiteSpace($purviewVersion)
    $purviewAuthorized = $milestone.Current.id -ne 'M0'

    $results.Add((New-JexValidationResult -Area 'Purview' -Check 'Milestone authorization' `
        -Status $(if ($purviewAuthorized) { 'Pass' } else { 'Skip' }) `
        -Message $(if ($purviewAuthorized) { "$($milestone.Current.id) is active, so Purview readiness may be evaluated." } else { 'Purview implementation is deferred during foundation milestone M0.' }) `
        -Remediation $(if ($purviewAuthorized) { '' } else { 'Do not install or wire Purview until a post-foundation milestone is explicitly activated.' })))

    $packageStatus = if ($isImplemented) { 'Pass' } elseif ($RequireImplemented) { 'Fail' } else { 'Skip' }
    $results.Add((New-JexValidationResult -Area 'Purview' -Check 'Agent Framework Purview package' `
        -Status $packageStatus `
        -Message $(if ($isImplemented) { "Microsoft.Agents.AI.Purview is pinned to $purviewVersion." } else { 'Microsoft.Agents.AI.Purview is not installed, as expected during M0.' }) `
        -Remediation $(if ($RequireImplemented -and -not $isImplemented) { 'Activate the milestone that owns Purview implementation and perform the coordinated dependency upgrade before adding middleware.' } else { '' })))

    if ($isImplemented) {
        $agentFrameworkParsed = ConvertTo-JexVersion -Value $agentFrameworkVersion
        $azureIdentityParsed = ConvertTo-JexVersion -Value $azureIdentityVersion
        $extensionsAiParsed = ConvertTo-JexVersion -Value $extensionsAiVersion
        foreach ($dependency in @(
            @{ Name = 'Microsoft.Agents.AI'; Current = $agentFrameworkParsed; Minimum = [version]'1.17.0' },
            @{ Name = 'Azure.Identity'; Current = $azureIdentityParsed; Minimum = [version]'1.21.0' },
            @{ Name = 'Microsoft.Extensions.AI'; Current = $extensionsAiParsed; Minimum = [version]'10.7.0' }
        )) {
            $valid = $null -ne $dependency.Current -and $dependency.Current -ge $dependency.Minimum
            $results.Add((New-JexValidationResult -Area 'Purview' -Check "$($dependency.Name) compatibility" `
                -Status $(if ($valid) { 'Pass' } else { 'Fail' }) `
                -Message $(if ($valid) { "Version $($dependency.Current) meets the Purview minimum." } else { "Version '$($dependency.Current)' is below the Purview minimum $($dependency.Minimum)." }) `
                -Remediation $(if ($valid) { '' } else { 'Upgrade the Microsoft dependency train together and run the full build/test gate.' })))
        }

        $hostSources = (Get-JexFirstPartyFiles `
            -Path (Join-Path $root 'server\agent-host') `
            -Extension @('.cs') |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
        $hostSources = [regex]::Replace($hostSources, '(?s:/\*.*?\*/)|(?m://.*$)', '')
        $purviewWired = $hostSources -match '\.WithPurview\s*\('
        $failClosed = $hostSources -match 'IgnoreExceptions\s*=\s*false'
        $userIdentity = $hostSources -match '\.SetUserId\s*\('
        $sensitiveTelemetryDisabled = $hostSources -match 'EnableSensitiveData\s*=\s*false'
        $middlewareOrder = Test-JexPurviewMiddlewareOrder -Source $hostSources
        foreach ($codeCheck in @(
            @{ Name = 'Purview middleware'; Valid = $purviewWired; Message = 'WithPurview is wired in the host.' },
            @{ Name = 'Fail-closed policy'; Valid = $failClosed; Message = 'Purview IgnoreExceptions is explicitly false.' },
            @{ Name = 'User policy identity'; Valid = $userIdentity; Message = 'Messages are associated with a Purview user ID.' },
            @{ Name = 'Sensitive telemetry disabled'; Valid = $sensitiveTelemetryDisabled; Message = 'Sensitive telemetry capture is explicitly disabled.' },
            @{ Name = 'Middleware order'; Valid = $middlewareOrder; Message = 'Purview wraps function invocation, which wraps OpenTelemetry.' }
        )) {
            $results.Add((New-JexValidationResult -Area 'Purview' -Check $codeCheck.Name `
                -Status $(if ($codeCheck.Valid) { 'Pass' } else { 'Fail' }) `
                -Message $(if ($codeCheck.Valid) { $codeCheck.Message } else { "$($codeCheck.Name) evidence is missing." })))
        }

        $purviewTestDirectory = Join-Path ([IO.Path]::GetTempPath()) "japan-expert-purview-tests-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $purviewTestDirectory -Force | Out-Null
        $priorRepositoryRoot = [Environment]::GetEnvironmentVariable(
            'JAPAN_EXPERT_REPOSITORY_ROOT',
            [EnvironmentVariableTarget]::Process)
        try {
            [Environment]::SetEnvironmentVariable(
                'JAPAN_EXPERT_REPOSITORY_ROOT',
                $root,
                [EnvironmentVariableTarget]::Process)
            $purviewTestProject = (Get-JexSourceLayout -RepositoryRoot $root).HostTestsProjectPath
            $purviewTests = Invoke-JexNativeCommand -FilePath 'dotnet' -ArgumentList @(
                'test',
                $purviewTestProject,
                '--configuration', 'Release',
                '--filter', 'TestCategory=Purview',
                '--logger', 'trx;LogFileName=purview.trx',
                '--results-directory', $purviewTestDirectory,
                '--artifacts-path', (Join-Path $purviewTestDirectory 'artifacts'),
                '--nologo'
            ) -WorkingDirectory $root
            $trxPath = Join-Path $purviewTestDirectory 'purview.trx'
            $testNames = @()
            $totalTests = 0
            $passedTests = 0
            if ($purviewTests.ExitCode -eq 0 -and (Test-Path -LiteralPath $trxPath -PathType Leaf)) {
                [xml]$trx = Get-Content -LiteralPath $trxPath -Raw
                $counters = $trx.SelectSingleNode("//*[local-name()='Counters']")
                if ($null -ne $counters) {
                    $totalTests = [int]$counters.total
                    $passedTests = [int]$counters.passed
                }
                $testNames = @($trx.SelectNodes("//*[local-name()='UnitTestResult']") |
                    ForEach-Object { [string]$_.testName })
            }

            $requiredEvidence = [ordered]@{
                BlockedInput  = 'BlockedInput'
                BlockedOutput = 'BlockedOutput'
                Streaming     = 'Streaming'
                FailClosed    = 'FailClosed'
                ToolArgument  = 'ToolArgument'
                ToolResult    = 'ToolResult'
                MiddlewareOrder = 'MiddlewareOrder'
            }
            $missingEvidence = @($requiredEvidence.GetEnumerator() | Where-Object {
                $pattern = $_.Value
                @($testNames | Where-Object { $_ -match $pattern }).Count -eq 0
            } | ForEach-Object { $_.Key })
            $behaviorTestsValid = $purviewTests.ExitCode -eq 0 -and
                $totalTests -ge $requiredEvidence.Count -and
                $passedTests -eq $totalTests -and
                $missingEvidence.Count -eq 0
            $purviewTestRemediation = if ($behaviorTestsValid) {
                ''
            }
            elseif ($purviewTests.ExitCode -ne 0 -and -not [string]::IsNullOrWhiteSpace($purviewTests.Output)) {
                $purviewTests.Output
            }
            else {
                'Add and pass MSTest tests categorized Purview for blocked input, blocked output, streaming, fail-closed behavior, tool arguments, tool results, and middleware ordering.'
            }
            $results.Add((New-JexValidationResult -Area 'Purview' -Check 'Executable Purview behavior tests' `
                -Status $(if ($behaviorTestsValid) { 'Pass' } else { 'Fail' }) `
                -Message $(if ($behaviorTestsValid) { "$passedTests categorized Purview behavior tests passed." } elseif ($purviewTests.ExitCode -ne 0) { 'The Purview behavior test process failed before usable results were produced.' } else { 'Executable Purview behavior evidence is incomplete or failing.' }) `
                -Remediation $purviewTestRemediation `
                -Data @{
                    ExitCode        = $purviewTests.ExitCode
                    Total           = $totalTests
                    Passed          = $passedTests
                    MissingEvidence = @($missingEvidence)
                }))
        }
        finally {
            [Environment]::SetEnvironmentVariable(
                'JAPAN_EXPERT_REPOSITORY_ROOT',
                $priorRepositoryRoot,
                [EnvironmentVariableTarget]::Process)
            Remove-Item -LiteralPath $purviewTestDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (($CheckTenantPolicy -or $ProbePolicy) -and -not $Online) {
        $results.Add((New-JexValidationResult -Area 'Purview' -Check 'Online switch' -Status 'Fail' `
            -Message 'Tenant policy checks and probes require -Online.' `
            -Remediation 'Add -Online only when tenant reads are intended.'))
        return @($results)
    }
    if ($Online -and -not $milestone.Current.allowsTenantReads) {
        $results.Add((New-JexValidationResult -Area 'Purview' -Check 'Milestone tenant-read authorization' -Status 'Fail' `
            -Message "Milestone '$($milestone.Current.id)' does not allow tenant reads." `
            -Remediation 'Do not run online validation until a reviewed milestone explicitly allows tenant reads.'))
        return @($results)
    }

    if ($CheckTenantPolicy) {
        $purviewTenantContext = @{}
        $connectionCommand = Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue
        if ($null -ne $connectionCommand) {
            try {
                $connection = @(Get-ConnectionInformation -ErrorAction Stop | Select-Object -First 1)
                if ($connection.Count -eq 1) {
                    $purviewTenantContext = @{
                        TenantId      = $connection[0].TenantID
                        ConnectionUri = $connection[0].ConnectionUri
                    }
                }
            }
            catch {
                $purviewTenantContext = @{ ContextError = $_.Exception.Message }
            }
        }
        $getFeatureConfiguration = Get-Command Get-FeatureConfiguration -ErrorAction SilentlyContinue
        if ($null -eq $getFeatureConfiguration) {
            $results.Add((New-JexValidationResult -Area 'Purview' -Check 'DSPM collection policy' -Status 'Fail' `
                -Message 'Get-FeatureConfiguration is unavailable in the current PowerShell session.' `
                -Remediation 'Install ExchangeOnlineManagement and connect to Security & Compliance PowerShell yourself, then retry.'))
        }
        else {
            try {
                $policies = @(Get-FeatureConfiguration `
                    -FeatureScenario KnowYourData `
                    -ErrorAction Stop)
                $matchingPolicies = @($policies | Where-Object {
                    $policyJson = $_ | ConvertTo-Json -Depth 20 -Compress
                    $_.Mode -eq 'Enable' -and
                        $policyJson -match 'Application' -and
                        $policyJson -match 'UploadText' -and
                        $policyJson -match 'DownloadText'
                })
                $hasRequiredCollectionPolicy = $matchingPolicies.Count -gt 0
                $purviewTenantContext.MatchingPolicyCount = $matchingPolicies.Count
                $results.Add((New-JexValidationResult -Area 'Purview' -Check 'DSPM collection policy' `
                    -Status $(if ($hasRequiredCollectionPolicy) { 'Pass' } else { 'Fail' }) `
                    -Message $(if ($hasRequiredCollectionPolicy) { 'An enabled policy uses the Application enforcement plane for upload and download text.' } else { 'No enabled policy shows the required Application, UploadText, and DownloadText configuration.' }) `
                    -Remediation $(if ($hasRequiredCollectionPolicy) { '' } else { 'Ask a Purview administrator to review the DSPM for AI collection policies.' }) `
                    -Data $purviewTenantContext))
            }
            catch {
                $results.Add((New-JexValidationResult -Area 'Purview' -Check 'DSPM collection policy' -Status 'Fail' `
                    -Message 'The DSPM collection policy could not be read.' -Remediation $_.Exception.Message))
            }
        }
    }

    if ($ProbePolicy) {
        $token = [Environment]::GetEnvironmentVariable($AccessTokenEnvironmentVariable, 'Process')
        if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($UserId) -or [string]::IsNullOrWhiteSpace($ApplicationId)) {
            $results.Add((New-JexValidationResult -Area 'Purview' -Check 'processContent probe' -Status 'Fail' `
                -Message 'The probe requires UserId, ApplicationId, and an access token in the named environment variable.' `
                -Remediation "Grant Content.Process.User or Content.Process.All, set $AccessTokenEnvironmentVariable in your shell, and pass non-secret IDs."))
        }
        else {
            $tokenContext = Get-JexJwtContext -Token $token
            $now = [DateTimeOffset]::UtcNow
            $operatingSystemPlatform = if ($IsWindows) {
                'Windows'
            }
            elseif ($IsLinux) {
                'Linux'
            }
            elseif ($IsMacOS) {
                'macOS'
            }
            else {
                'Unknown'
            }
            $entry = [ordered]@{
                '@odata.type'   = 'microsoft.graph.processConversationMetadata'
                identifier      = [guid]::NewGuid().ToString()
                content         = [ordered]@{
                    '@odata.type' = 'microsoft.graph.textContent'
                    data          = $ProbeText
                }
                name            = 'Japan Tourist Assistant validation probe'
                correlationId   = [guid]::NewGuid().ToString()
                sequenceNumber  = 0
                isTruncated     = $false
                createdDateTime = $now.ToString('o')
                modifiedDateTime = $now.ToString('o')
            }
            if ($BlueprintId -and $AgentInstanceId) {
                $entry.agents = @([ordered]@{
                    '@odata.type' = 'microsoft.graph.aiAgentInfo'
                    blueprintId   = $BlueprintId
                    identifier    = $AgentInstanceId
                    name          = 'Japan Tourist Assistant'
                    version       = '1.0'
                })
            }
            $requestBody = [ordered]@{
                contentToProcess = [ordered]@{
                    contentEntries = @($entry)
                    activityMetadata = [ordered]@{ activity = 'uploadText' }
                    deviceMetadata = [ordered]@{
                        deviceType = 'Unmanaged'
                        operatingSystemSpecifications = [ordered]@{
                            operatingSystemPlatform = $operatingSystemPlatform
                            operatingSystemVersion = [Runtime.InteropServices.RuntimeInformation]::OSDescription
                        }
                        ipAddress = '127.0.0.1'
                    }
                    protectedAppMetadata = [ordered]@{
                        name = 'Japan Tourist Assistant'
                        version = '1.0'
                        applicationLocation = [ordered]@{
                            '@odata.type' = 'microsoft.graph.policyLocationApplication'
                            value = $ApplicationId
                        }
                    }
                    integratedAppMetadata = [ordered]@{
                        name = 'Japan Tourist Assistant validation tools'
                        version = '1.0'
                    }
                }
            }
            try {
                $encodedUserId = [Uri]::EscapeDataString($UserId)
                $webResponse = Invoke-WebRequest `
                    -Method Post `
                    -Uri "https://graph.microsoft.com/v1.0/users/$encodedUserId/dataSecurityAndGovernance/processContent" `
                    -Headers @{ Authorization = "Bearer $token"; 'Client-Request-Id' = [guid]::NewGuid().ToString() } `
                    -ContentType 'application/json' `
                    -Body ($requestBody | ConvertTo-Json -Depth 20 -Compress) `
                    -TimeoutSec $ProbeTimeoutSeconds `
                    -SkipHttpErrorCheck
                $statusCode = [int]$webResponse.StatusCode
                $connectivitySucceeded = $statusCode -in @(200, 202, 204)
                $results.Add((New-JexValidationResult -Area 'Purview' -Check 'processContent connectivity' `
                    -Status $(if ($connectivitySucceeded) { 'Pass' } else { 'Fail' }) `
                    -Message $(if ($connectivitySucceeded) { "Microsoft Graph accepted the synthetic probe with HTTP $statusCode." } else { "Microsoft Graph returned HTTP $statusCode." }) `
                    -Remediation $(if ($connectivitySucceeded) { '' } else { 'Verify Content.Process permissions, licensing, user/application IDs, and token validity.' }) `
                    -Data @{
                        StatusCode    = $statusCode
                        TenantId      = $tokenContext.TenantId
                        TokenClientId = $tokenContext.ClientId
                        TargetUserId  = $UserId
                        ApplicationId = $ApplicationId
                    }))
                if ($connectivitySucceeded) {
                    $results.Add((Get-JexPurviewEnforcementResult `
                        -StatusCode $statusCode `
                        -Content $webResponse.Content `
                        -ExpectBlock:$ExpectBlock))
                }
            }
            catch {
                $results.Add((New-JexValidationResult -Area 'Purview' -Check 'processContent connectivity' -Status 'Fail' `
                    -Message 'Microsoft Graph processContent failed.' `
                    -Remediation 'Verify Content.Process permissions, user/application IDs, licensing, policy configuration, and token validity.' `
                    -Data @{ Error = $_.Exception.Message }))
            }
        }
    }

    @($results)
}

function Get-JexFreeTcpPort {
    [CmdletBinding()]
    param()

    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
}

function Get-JexLogTail {
    [CmdletBinding()]
    param(
        [string] $StandardOutputPath,
        [string] $StandardErrorPath,
        [int] $LineCount = 30
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($path in @($StandardOutputPath, $StandardErrorPath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            foreach ($line in @(Get-Content -LiteralPath $path -Tail $LineCount)) {
                $lines.Add($line)
            }
        }
    }
    ($lines | Select-Object -Last $LineCount) -join [Environment]::NewLine
}

function Wait-JexHealthEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Uri] $Uri,

        [Parameter(Mandatory)]
        [Diagnostics.Process] $Process,

        [ValidateRange(1, 120)]
        [int] $TimeoutSeconds = 20,

        [string[]] $ExpectedStatus = @('healthy')
    )

    $client = [Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds(2)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $lastError = ''
    try {
        while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            $Process.Refresh()
            if ($Process.HasExited) {
                return [pscustomobject]@{
                    Healthy    = $false
                    StatusCode = $null
                    Body       = ''
                    Error      = "Process exited with code $($Process.ExitCode)."
                }
            }

            try {
                $response = $client.GetAsync($Uri).GetAwaiter().GetResult()
                $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                if ($response.IsSuccessStatusCode) {
                    try {
                        $payload = $body | ConvertFrom-Json -Depth 10
                        if ($payload.status -in $ExpectedStatus) {
                            return [pscustomobject]@{
                                Healthy    = $true
                                StatusCode = [int]$response.StatusCode
                                Body       = $body
                                Error      = ''
                            }
                        }
                        $lastError = "Health response status was not one of '$($ExpectedStatus -join ',')': $body"
                    }
                    catch {
                        $lastError = "Health response was not valid JSON: $body"
                    }
                }
                else {
                    $lastError = "HTTP $([int]$response.StatusCode): $body"
                }
            }
            catch {
                $lastError = $_.Exception.Message
            }

            [Threading.Tasks.Task]::Delay(200).GetAwaiter().GetResult()
        }

        [pscustomobject]@{
            Healthy    = $false
            StatusCode = $null
            Body       = ''
            Error      = "Health endpoint timed out after $TimeoutSeconds seconds. Last error: $lastError"
        }
    }
    finally {
        $client.Dispose()
    }
}

function Stop-JexProcessTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Diagnostics.Process] $Process,

        [ValidateRange(100, 30000)]
        [int] $TimeoutMilliseconds = 5000
    )

    $Process.Refresh()
    if ($Process.HasExited) {
        return $true
    }

    try {
        if ($IsWindows) {
            $taskKill = Invoke-JexNativeCommand -FilePath 'taskkill.exe' -ArgumentList @(
                '/PID', $Process.Id.ToString(), '/T', '/F'
            )
            if ($taskKill.ExitCode -ne 0) {
                $Process.Refresh()
                if (-not $Process.HasExited) {
                    return $false
                }
            }
        }
        else {
            Stop-Process -Id $Process.Id -Force -ErrorAction Stop
        }

        $exited = $Process.WaitForExit($TimeoutMilliseconds)
        $Process.Refresh()
        $exited -and $Process.HasExited
    }
    catch {
        $false
    }
}

function Invoke-JexLocalCi {
    [CmdletBinding()]
    param(
        [string] $RepositoryRoot = $script:DefaultRepositoryRoot,

        [ValidateSet('Debug', 'Release')]
        [string] $Configuration = 'Release',

        [ValidateRange(1, 120)]
        [int] $HealthTimeoutSeconds = 20,

        [switch] $SkipToolsSelfTest,

        [switch] $SkipBuild,

        [switch] $SkipTests,

        [switch] $SkipHealth
    )

    $root = Resolve-JexRepositoryRoot -RepositoryRoot $RepositoryRoot
    $results = [System.Collections.Generic.List[object]]::new()
    $layout = Get-JexSourceLayout -RepositoryRoot $root
    if (@($layout.UnresolvedPaths).Count -gt 0) {
        return ,(New-JexValidationResult -Area 'LocalCI' -Check 'Source layout discovery' -Status 'Fail' `
            -Message 'Local CI could not resolve the solution or one of the host and MCP projects.' `
            -Remediation 'Finish the in-flight project rename and remove duplicate or leftover project directories.' `
            -Data @{ UnresolvedPaths = @($layout.UnresolvedPaths) })
    }
    $solutionPath = $layout.SolutionPath
    $runDirectory = Join-Path ([IO.Path]::GetTempPath()) "japan-expert-ci-$([guid]::NewGuid())"
    $artifactsDirectory = Join-Path $runDirectory 'artifacts'
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

    if (-not $SkipToolsSelfTest) {
        $selfTest = Invoke-JexNativeCommand -FilePath 'pwsh' -ArgumentList @(
            '-NoLogo', '-NoProfile', '-File',
            (Join-Path $root 'tools\tests\Invoke-ToolsSelfTest.ps1'),
            '-RepositoryRoot', $root
        ) -WorkingDirectory $root
        $results.Add((New-JexValidationResult -Area 'LocalCI' -Check 'Tools self-test' `
            -Status $(if ($selfTest.ExitCode -eq 0) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($selfTest.ExitCode -eq 0) { 'PowerShell validation tools passed their self-tests.' } else { 'PowerShell validation tools failed their self-tests.' }) `
            -Remediation $(if ($selfTest.ExitCode -eq 0) { '' } else { $selfTest.Output }) `
            -Data @{ ExitCode = $selfTest.ExitCode }))
    }

    if (-not $SkipBuild) {
        $build = Invoke-JexNativeCommand -FilePath 'dotnet' -ArgumentList @(
            'build', $solutionPath,
            '--configuration', $Configuration,
            '--artifacts-path', $artifactsDirectory,
            '--nologo'
        ) -WorkingDirectory $root
        $results.Add((New-JexValidationResult -Area 'LocalCI' -Check 'Solution build' `
            -Status $(if ($build.ExitCode -eq 0) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($build.ExitCode -eq 0) { "$Configuration solution build passed." } else { "$Configuration solution build failed." }) `
            -Remediation $(if ($build.ExitCode -eq 0) { '' } else { $build.Output }) `
            -Data @{ ExitCode = $build.ExitCode; Configuration = $Configuration }))
    }

    $buildFailed = @($results | Where-Object { $_.Check -eq 'Solution build' -and $_.Status -eq 'Fail' }).Count -gt 0
    if (-not $SkipTests -and -not $buildFailed) {
        $testArguments = @('test', $solutionPath, '--configuration', $Configuration, '--nologo')
        if (-not $SkipBuild) {
            $testArguments += '--no-build'
        }
        $testArguments += @('--artifacts-path', $artifactsDirectory)
        $priorRepositoryRoot = [Environment]::GetEnvironmentVariable(
            'JAPAN_EXPERT_REPOSITORY_ROOT',
            [EnvironmentVariableTarget]::Process)
        try {
            [Environment]::SetEnvironmentVariable(
                'JAPAN_EXPERT_REPOSITORY_ROOT',
                $root,
                [EnvironmentVariableTarget]::Process)
            $tests = Invoke-JexNativeCommand -FilePath 'dotnet' -ArgumentList $testArguments -WorkingDirectory $root
        }
        finally {
            [Environment]::SetEnvironmentVariable(
                'JAPAN_EXPERT_REPOSITORY_ROOT',
                $priorRepositoryRoot,
                [EnvironmentVariableTarget]::Process)
        }
        $results.Add((New-JexValidationResult -Area 'LocalCI' -Check 'Solution tests' `
            -Status $(if ($tests.ExitCode -eq 0) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($tests.ExitCode -eq 0) { "$Configuration solution tests passed." } else { "$Configuration solution tests failed." }) `
            -Remediation $(if ($tests.ExitCode -eq 0) { '' } else { $tests.Output }) `
            -Data @{ ExitCode = $tests.ExitCode; Configuration = $Configuration }))
    }
    elseif (-not $SkipTests) {
        $results.Add((New-JexValidationResult -Area 'LocalCI' -Check 'Solution tests' -Status 'Skip' `
            -Message 'Tests were skipped because the solution build failed.'))
    }

    if ($SkipHealth -or $buildFailed) {
        if (-not $SkipHealth) {
            $results.Add((New-JexValidationResult -Area 'LocalCI' -Check 'Service health' -Status 'Skip' `
                -Message 'Service health was skipped because the solution build failed.'))
        }
        Remove-Item -LiteralPath $runDirectory -Recurse -Force -ErrorAction SilentlyContinue
        return @($results)
    }

    $services = @(
        @{
            Name       = 'Agent host'
            ProjectPath = $layout.HostProjectPath
            HealthChecks = @(
                @{ Name = 'Agent host health'; Path = '/api/health'; ExpectedStatus = @('healthy') },
                @{ Name = 'Agent host liveness'; Path = '/api/health/live'; ExpectedStatus = @('healthy') },
                @{ Name = 'Agent host readiness'; Path = '/api/health/ready'; ExpectedStatus = @('healthy', 'degraded') }
            )
        },
        @{
            Name       = 'Attractions MCP'
            ProjectPath = $layout.McpServiceProjects['attractions']
            HealthChecks = @(@{ Name = 'Attractions MCP health'; Path = '/health'; ExpectedStatus = @('healthy') })
        },
        @{
            Name       = 'Weather MCP'
            ProjectPath = $layout.McpServiceProjects['weather']
            HealthChecks = @(@{ Name = 'Weather MCP health'; Path = '/health'; ExpectedStatus = @('healthy') })
        },
        @{
            Name       = 'Accommodation MCP'
            ProjectPath = $layout.McpServiceProjects['accommodation']
            HealthChecks = @(@{ Name = 'Accommodation MCP health'; Path = '/health'; ExpectedStatus = @('healthy') })
        },
        @{
            Name       = 'Currency MCP'
            ProjectPath = $layout.McpServiceProjects['currency']
            HealthChecks = @(@{ Name = 'Currency MCP health'; Path = '/health'; ExpectedStatus = @('healthy') })
        }
    )

    $processes = [System.Collections.Generic.List[object]]::new()
    $cleanupFailures = [System.Collections.Generic.List[string]]::new()
    $originalEnvironment = [Environment]::GetEnvironmentVariable('ASPNETCORE_ENVIRONMENT', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('ASPNETCORE_ENVIRONMENT', 'Development', 'Process')
        foreach ($service in $services) {
            $projectDirectory = Split-Path -Parent $service.ProjectPath
            $projectName = [IO.Path]::GetFileNameWithoutExtension($service.ProjectPath)
            $assemblyPath = Join-Path $artifactsDirectory "bin\$projectName\$($Configuration.ToLowerInvariant())\$projectName.dll"
            if (-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) {
                $results.Add((New-JexValidationResult -Area 'LocalCI' -Check "$($service.Name) health" -Status 'Fail' `
                    -Message "Compiled assembly is missing: $assemblyPath" `
                    -Remediation 'Run the solution build before health validation.'))
                continue
            }

            $port = Get-JexFreeTcpPort
            $baseUri = "http://127.0.0.1:$port"
            $safeName = $service.Name.Replace(' ', '-').ToLowerInvariant()
            $standardOutputPath = Join-Path $runDirectory "$safeName.stdout.log"
            $standardErrorPath = Join-Path $runDirectory "$safeName.stderr.log"
            try {
                $process = Start-Process `
                    -FilePath 'dotnet' `
                    -ArgumentList @($assemblyPath, '--urls', $baseUri) `
                    -WorkingDirectory $projectDirectory `
                    -RedirectStandardOutput $standardOutputPath `
                    -RedirectStandardError $standardErrorPath `
                    -PassThru
                $processes.Add([pscustomobject]@{
                    Service             = $service
                    Process             = $process
                    Port                = $port
                    BaseUri             = $baseUri
                    StandardOutputPath  = $standardOutputPath
                    StandardErrorPath   = $standardErrorPath
                })
            }
            catch {
                $results.Add((New-JexValidationResult -Area 'LocalCI' -Check "$($service.Name) health" -Status 'Fail' `
                    -Message 'Service process could not be started.' -Remediation $_.Exception.Message))
            }
        }

        foreach ($entry in $processes) {
            foreach ($healthCheck in $entry.Service.HealthChecks) {
                $healthUri = [Uri]::new("$($entry.BaseUri)$($healthCheck.Path)")
                $health = Wait-JexHealthEndpoint `
                    -Uri $healthUri `
                    -Process $entry.Process `
                    -TimeoutSeconds $HealthTimeoutSeconds `
                    -ExpectedStatus $healthCheck.ExpectedStatus
                $logTail = if ($health.Healthy) {
                    ''
                }
                else {
                    Get-JexLogTail `
                        -StandardOutputPath $entry.StandardOutputPath `
                        -StandardErrorPath $entry.StandardErrorPath
                }
                $statusValue = if ($health.Healthy) {
                    ($health.Body | ConvertFrom-Json -Depth 10).status
                }
                else {
                    ''
                }
                $results.Add((New-JexValidationResult -Area 'LocalCI' -Check $healthCheck.Name `
                    -Status $(if ($health.Healthy) { 'Pass' } else { 'Fail' }) `
                    -Message $(if ($health.Healthy) { "Health endpoint returned HTTP $($health.StatusCode) with status=$statusValue." } else { $health.Error }) `
                    -Remediation $logTail `
                    -Data @{
                        Uri        = $healthUri.AbsoluteUri
                        Port       = $entry.Port
                        ProcessId  = $entry.Process.Id
                        StatusCode = $health.StatusCode
                        Status     = $statusValue
                    }))
            }
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable('ASPNETCORE_ENVIRONMENT', $originalEnvironment, 'Process')
        foreach ($entry in $processes) {
            try {
                if (-not (Stop-JexProcessTree -Process $entry.Process)) {
                    $cleanupFailures.Add("Process:$($entry.Process.Id)")
                }
            }
            catch {
                $cleanupFailures.Add("Process:$($entry.Process.Id)")
                Write-Verbose "Could not stop process $($entry.Process.Id): $($_.Exception.Message)"
            }
            finally {
                $entry.Process.Dispose()
            }
        }
        Remove-Item -LiteralPath $runDirectory -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $runDirectory) {
            $cleanupFailures.Add("TempDirectory:$runDirectory")
        }
    }

    $results.Add((New-JexValidationResult -Area 'LocalCI' -Check 'Process cleanup' `
        -Status $(if ($cleanupFailures.Count -eq 0) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($cleanupFailures.Count -eq 0) { 'All temporary host and MCP processes were terminated.' } else { 'One or more temporary service processes could not be terminated.' }) `
        -Remediation $(if ($cleanupFailures.Count -eq 0) { '' } else { 'Stop the reported processes and remove temporary directories before rerunning local CI.' }) `
        -Data @{ CleanupFailures = @($cleanupFailures); ProcessCount = $processes.Count }))

    @($results)
}

function Write-JexValidationResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [object[]] $Results,

        [ValidateSet('Text', 'Json')]
        [string] $OutputFormat = 'Text'
    )

    $allResults = @($Results)
    if ($OutputFormat -eq 'Json') {
        $summary = [ordered]@{
            Passed  = @($allResults | Where-Object Status -eq 'Pass').Count
            Warnings = @($allResults | Where-Object Status -eq 'Warn').Count
            Failed  = @($allResults | Where-Object Status -eq 'Fail').Count
            Skipped = @($allResults | Where-Object Status -eq 'Skip').Count
        }
        [pscustomobject]@{ Summary = $summary; Results = $allResults } | ConvertTo-Json -Depth 12
        return
    }

    foreach ($result in $allResults) {
        Write-Output "[$($result.Status.ToUpperInvariant())] $($result.Area)/$($result.Check): $($result.Message)"
        if ($result.Remediation) {
            Write-Output "  Remediation: $($result.Remediation)"
        }
    }

    $passCount = @($allResults | Where-Object Status -eq 'Pass').Count
    $warningCount = @($allResults | Where-Object Status -eq 'Warn').Count
    $failureCount = @($allResults | Where-Object Status -eq 'Fail').Count
    $skipCount = @($allResults | Where-Object Status -eq 'Skip').Count
    Write-Output "Summary: $passCount passed, $warningCount warnings, $failureCount failed, $skipCount skipped."
}

function Get-JexValidationExitCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Results,

        [switch] $Strict
    )

    if (@($Results).Count -eq 0) {
        return 1
    }
    if (@($Results | Where-Object Status -eq 'Fail').Count -gt 0) {
        return 1
    }
    if ($Strict -and @($Results | Where-Object Status -eq 'Warn').Count -gt 0) {
        return 1
    }
    0
}

Export-ModuleMember -Function @(
    'ConvertTo-JexVersion',
    'Find-JexCommittedIdentifier',
    'Find-JexRetiredSymbol',
    'Find-JexSyntheticSensitiveData',
    'Find-JexPotentialSecrets',
    'Find-JexForbiddenToolMutation',
    'Find-JexM0ImplementationMarker',
    'Get-JexDeploymentPolicy',
    'Get-JexAgentHostRequiredSettings',
    'Get-JexExpectedDeploymentNames',
    'Get-JexFoundryRuntimeAccessPolicy',
    'Get-JexMcpProviderSection',
    'Get-JexMilestoneState',
    'Get-JexPackageVersion',
    'Get-JexFirstPartyFiles',
    'Get-JexFreeTcpPort',
    'Get-JexPurviewEnforcementResult',
    'Get-JexSecretStoreRequirement',
    'Get-JexSourceLayout',
    'Get-JexSyntheticCasePolicy',
    'Get-JexValidationExitCode',
    'Invoke-JexValidationSafely',
    'Stop-JexProcessTree',
    'New-JexValidationResult',
    'Resolve-JexRepositoryRoot',
    'Test-JexPrerequisites',
    'Test-JexAzureReadiness',
    'Test-JexDeploymentBoundary',
    'Test-JexMcpProviderConfiguration',
    'Test-JexPurviewReadiness',
    'Test-JexPurviewMiddlewareOrder',
    'Test-JexRepositoryConfiguration',
    'Invoke-JexLocalCi',
    'Write-JexValidationResults'
)
