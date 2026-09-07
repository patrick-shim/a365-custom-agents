Set-StrictMode -Version Latest

$script:DefaultRepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

function New-StaValidationResult {
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

function Invoke-StaValidationSafely {
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
        New-StaValidationResult `
            -Area 'Tooling' `
            -Check $Check `
            -Status 'Fail' `
            -Message 'Validation could not complete because of an unexpected local error.' `
            -Remediation 'Review local paths and configuration, then rerun the command.' `
            -Data @{ ExceptionType = $_.Exception.GetType().FullName }
    }
}

function Resolve-StaRepositoryRoot {
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    if (-not (Test-Path -LiteralPath $RepositoryRoot -PathType Container)) {
        throw "Repository root does not exist: $RepositoryRoot"
    }

    (Resolve-Path -LiteralPath $RepositoryRoot).Path
}

function Invoke-StaNativeCommand {
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

function ConvertTo-StaVersion {
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

function Get-StaJwtContext {
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

function Find-StaM0ImplementationMarker {
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

function Find-StaForbiddenToolMutation {
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

    function Get-StaContainingFunctionName {
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

    function Get-StaNamedArgumentAst {
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

    function Get-StaConstantString {
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

    function Get-StaLiteralArgumentStrings {
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
            $containingFunction = Get-StaContainingFunctionName -Node $command
            if ($containingFunction -ne 'Invoke-StaNativeCommand') {
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
        if ($normalizedName -eq 'invoke-stanativecommand') {
            $targetParameter = 'FilePath'
            $targetAst = Get-StaNamedArgumentAst -Command $command -ParameterName $targetParameter
            $target = Get-StaConstantString -Node $targetAst
            $cloudTargets = @('a365', 'a365.exe', 'az', 'az.cmd', 'atk', 'atk.ps1', 'atk.cmd')
            if ([string]::IsNullOrWhiteSpace($target)) {
                if ((Get-StaContainingFunctionName -Node $command) -ne 'Invoke-StaNativeCommand') {
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
            $argumentAst = Get-StaNamedArgumentAst -Command $command -ParameterName 'ArgumentList'
            if ($null -eq $argumentAst) {
                [pscustomobject]@{ Source = $Source; Mutation = 'Dynamic cloud CLI arguments'; Command = $extent }
                continue
            }
            $literalArguments = @(Get-StaLiteralArgumentStrings -Node $argumentAst)
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

function Get-StaMilestoneState {
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-StaRepositoryRoot -RepositoryRoot $RepositoryRoot
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

function Get-StaPackageVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $PackageName,

        [string] $RepositoryRoot = $script:DefaultRepositoryRoot
    )

    $root = Resolve-StaRepositoryRoot -RepositoryRoot $RepositoryRoot
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

function Get-StaFirstPartyFiles {
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

function Test-StaPrerequisites {
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
            New-StaValidationResult -Area 'Prerequisites' -Check $requirement.Name -Status 'Fail' `
                -Message "$($requirement.Command) is not installed or is not on PATH." `
                -Remediation "Restore or install $($requirement.Name) and run this check again."
            continue
        }

        if ($SkipCloudCliVersionCommands -and $requirement.Command -eq 'az') {
            New-StaValidationResult -Area 'Prerequisites' -Check $requirement.Name -Status 'Skip' `
                -Message "$($requirement.Command) is available, but its version command was not executed in offline aggregate validation." `
                -Data @{
                    Command         = $resolvedCli.FilePath
                    Source          = $resolvedCli.Source
                    CommandExecuted = $false
                }
            continue
        }

        $workingDirectory = Resolve-StaRepositoryRoot -RepositoryRoot $RepositoryRoot
        $invocation = switch ($requirement.Command) {
            'dotnet' { Invoke-StaNativeCommand -FilePath 'dotnet' -ArgumentList @('--version') -WorkingDirectory $workingDirectory; break }
            'pwsh' { Invoke-StaNativeCommand -FilePath 'pwsh' -ArgumentList @('--version') -WorkingDirectory $workingDirectory; break }
            'az' { Invoke-StaNativeCommand -FilePath 'az' -ArgumentList @('version', '--output', 'json') -WorkingDirectory $workingDirectory; break }
            'git' { Invoke-StaNativeCommand -FilePath 'git' -ArgumentList @('--version') -WorkingDirectory $workingDirectory; break }
            default { [pscustomobject]@{ ExitCode = -1; Output = "Unsupported prerequisite command: $($requirement.Command)" } }
        }
        if ($invocation.ExitCode -ne 0) {
            New-StaValidationResult -Area 'Prerequisites' -Check $requirement.Name -Status 'Fail' `
                -Message "$($requirement.Command) returned exit code $($invocation.ExitCode)." `
                -Remediation $invocation.Output
            continue
        }

        $version = ConvertTo-StaVersion -Value $invocation.Output
        if ($null -eq $version) {
            New-StaValidationResult -Area 'Prerequisites' -Check $requirement.Name -Status 'Warn' `
                -Message "$($requirement.Command) is available, but its version could not be parsed." `
                -Data @{ Output = $invocation.Output }
            continue
        }

        if ($version -lt $requirement.Minimum) {
            New-StaValidationResult -Area 'Prerequisites' -Check $requirement.Name -Status 'Fail' `
                -Message "Version $version is below the required $($requirement.Minimum)." `
                -Remediation "Upgrade $($requirement.Name)." `
                -Data @{ Version = $version.ToString(); Minimum = $requirement.Minimum.ToString() }
            continue
        }

        New-StaValidationResult -Area 'Prerequisites' -Check $requirement.Name -Status 'Pass' `
            -Message "Version $version is available." `
            -Data @{ Version = $version.ToString(); Command = $resolvedCli.FilePath; Source = $resolvedCli.Source }
    }

    @($results)
}

function Find-StaPotentialSecrets {
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-StaRepositoryRoot -RepositoryRoot $RepositoryRoot
    $candidateFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {
        $_.FullName -notmatch '[\\/](?:bin|obj|build|node_modules|\.git|\.azure|\.copilot-azure|\.a365|teams)[\\/]' -and
        $_.Name -notin @('a365.generated.config.json', 'ToolingManifest.json') -and
        ($_.Name -eq '.env' -or $_.Name -like '.env.*' -or
            $_.Extension -in @('.json', '.yml', '.yaml', '.config', '.xml'))
    })
    $findings = [System.Collections.Generic.List[string]]::new()
    $assignmentPattern = [regex]'(?im)^\s*["'']?(?<key>[a-z0-9_.-]+)["'']?\s*[:=]\s*["'']?(?<value>[^\r\n"'']*)'

    function Test-StaSecretValue {
        param([AllowNull()][object] $Value)

        if ($null -eq $Value -or $Value -isnot [string]) {
            return $false
        }
        $text = $Value.Trim()
        $text -and $text -notmatch '^(?:<.*>|\$\{\{.*\}\}|\$\(.*\)|\$\{.*\}|null|false|true)$'
    }

    function Find-StaJsonSecretProperty {
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
                        (Test-StaSecretValue -Value $property.Value.GetString())) {
                        $childPath
                    }
                    Find-StaJsonSecretProperty -Node $property.Value -PropertyPath $childPath
                }
                break
            }
            ([Text.Json.JsonValueKind]::Array) {
                $index = 0
                foreach ($item in $Node.EnumerateArray()) {
                    Find-StaJsonSecretProperty -Node $item -PropertyPath "$PropertyPath[$index]"
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
                foreach ($propertyPath in @(Find-StaJsonSecretProperty -Node $jsonDocument.RootElement)) {
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
                if (Test-StaSecretValue -Value $value) {
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

function Test-StaRepositoryConfiguration {
    [CmdletBinding()]
    param([string] $RepositoryRoot = $script:DefaultRepositoryRoot)

    $root = Resolve-StaRepositoryRoot -RepositoryRoot $RepositoryRoot
    $requiredPaths = @(
        'KoreaExpertAgent.slnx',
        'Directory.Packages.props',
        'server\agent\KoreaExpert.Agent\KoreaExpert.Agent.csproj',
        'server\agent-host\KoreaExpert.AgentHost\KoreaExpert.AgentHost.csproj',
        'contracts\frontend-backend-contract.json',
        'contracts\frontend-backend-contract.schema.json',
        'docs\milestones\milestones.json'
    )
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($relativePath in $requiredPaths) {
        $exists = Test-Path -LiteralPath (Join-Path $root $relativePath)
        $results.Add((New-StaValidationResult -Area 'Repository' -Check "Path: $relativePath" `
            -Status $(if ($exists) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($exists) { 'Required path exists.' } else { 'Required path is missing.' }) `
            -Remediation $(if ($exists) { '' } else { "Restore $relativePath." })))
    }

    try {
        $milestone = Get-StaMilestoneState -RepositoryRoot $root
        $validState = $milestone.Current.status -eq 'active'
        $results.Add((New-StaValidationResult -Area 'Repository' -Check 'Milestone state' `
            -Status $(if ($validState) { 'Pass' } else { 'Fail' }) `
            -Message "Current milestone is $($milestone.Current.id) with status '$($milestone.Current.status)'." `
            -Remediation $(if ($validState) { '' } else { 'Set exactly one current milestone to active through a reviewed protocol transition.' })))
    }
    catch {
        $results.Add((New-StaValidationResult -Area 'Repository' -Check 'Milestone state' -Status 'Fail' `
            -Message $_.Exception.Message -Remediation 'Repair docs/milestones/milestones.json.'))
        $milestone = $null
    }

    $agentFrameworkVersion = Get-StaPackageVersion -PackageName 'Microsoft.Agents.AI' -RepositoryRoot $root
    $a365RuntimeVersion = Get-StaPackageVersion -PackageName 'Microsoft.Agents.A365.Runtime' -RepositoryRoot $root
    $mcpClientVersion = Get-StaPackageVersion -PackageName 'ModelContextProtocol' -RepositoryRoot $root
    foreach ($package in @(
        @{ Name = 'Microsoft Agent Framework'; Version = $agentFrameworkVersion },
        @{ Name = 'Agent 365 runtime'; Version = $a365RuntimeVersion },
        @{ Name = 'Official MCP client'; Version = $mcpClientVersion }
    )) {
        $present = -not [string]::IsNullOrWhiteSpace($package.Version)
        $results.Add((New-StaValidationResult -Area 'Repository' -Check $package.Name `
            -Status $(if ($present) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($present) { "Package is centrally pinned to $($package.Version)." } else { 'Required package pin is missing.' }) `
            -Remediation $(if ($present) { '' } else { 'Add the package to Directory.Packages.props.' })))
    }

    $programPath = Join-Path $root 'server\agent-host\KoreaExpert.AgentHost\Program.cs'
    $applicationPath = Join-Path $root 'server\agent-host\KoreaExpert.AgentHost\KoreaExpertApplication.cs'
    $hostSettingsPath = Join-Path $root 'server\agent-host\KoreaExpert.AgentHost\appsettings.json'
    $oboExchangePath = Join-Path $root 'server\agent-host\KoreaExpert.AgentHost\AgentIdentityOboTokenExchange.cs'
    $frontendIdentityBindingPath = Join-Path $root 'server\agent-host\KoreaExpert.AgentHost\AgentFrontendIdentityBinding.cs'
    $internalMcpOptionsPath = Join-Path $root 'server\agent-host\KoreaExpert.AgentHost\InternalMcpOptions.cs'
    $internalMcpCatalogPath = Join-Path $root 'server\agent-host\KoreaExpert.AgentHost\InternalMcpToolCatalog.cs'
    $authorizationTestsPath = Join-Path $root 'tests\KoreaExpert.AgentHost.Tests\AgentIdentityAuthorizationOptionsTests.cs'
    $oboExchangeTestsPath = Join-Path $root 'tests\KoreaExpert.AgentHost.Tests\AgentIdentityOboTokenExchangeTests.cs'
    $frontendIdentityBindingTestsPath = Join-Path $root 'tests\KoreaExpert.AgentHost.Tests\AgentFrontendIdentityBindingTests.cs'
    $observabilityTokenCacheTestsPath = Join-Path $root 'tests\KoreaExpert.AgentHost.Tests\ObservabilityTokenCacheTests.cs'
    $internalMcpCatalogTestsPath = Join-Path $root 'tests\KoreaExpert.AgentHost.Tests\InternalMcpToolCatalogTests.cs'
    $mcpAuthorizationPath = Join-Path $root 'server\mcp\shared\KoreaExpert.Mcp.Hosting\McpWorkloadAuthorization.cs'
    $mcpAuthorizationTestsPath = Join-Path $root 'tests\KoreaExpert.Mcp.Hosting.Tests\McpWorkloadAuthorizationTests.cs'
    $promptShieldPath = Join-Path $root 'server\agent-host\KoreaExpert.AgentHost\PromptShieldGuard.cs'
    $promptShieldToolContentPath = Join-Path $root 'server\agent-host\KoreaExpert.AgentHost\PromptShieldToolContentEvaluator.cs'
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
    $promptShieldContent = Get-Content -LiteralPath $promptShieldPath -Raw
    $promptShieldToolContent = Get-Content -LiteralPath $promptShieldToolContentPath -Raw
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

    $hostSourceDirectory = Join-Path $root 'server\agent-host\KoreaExpert.AgentHost'
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

    # PROMPT SHIELDS: both surfaces must stay screened and every failure path must reject the turn.
    # The user prompt is screened before the model, and tool results are screened because Purview
    # chat middleware does not inspect them.
    $promptShieldGuardPresent = $promptShieldContent.Contains('PromptShieldSurface.UserPrompt', [StringComparison]::Ordinal) -and
        $promptShieldContent.Contains('PromptShieldSurface.Document', [StringComparison]::Ordinal) -and
        $promptShieldContent.Contains('contentsafety/text:shieldPrompt', [StringComparison]::Ordinal) -and
        $promptShieldContent.Contains('throw new PromptShieldBlockedException', [StringComparison]::Ordinal) -and
        $promptShieldContent.Contains('throw new PromptShieldEvaluationException', [StringComparison]::Ordinal)
    $promptShieldFailsClosed = $applicationContent.Contains('_promptShieldGuard.EvaluateAsync', [StringComparison]::Ordinal) -and
        $applicationContent.Contains('catch (PromptShieldBlockedException)', [StringComparison]::Ordinal) -and
        $applicationContent.Contains('_promptShieldOptions.EvaluationFailureMessage', [StringComparison]::Ordinal) -and
        $promptShieldToolContent.Contains('PromptShieldSurface.Document', [StringComparison]::Ordinal) -and
        $programContent.Contains('CompositeToolContentEvaluator', [StringComparison]::Ordinal)
    $promptShieldKeyless = -not ($promptShieldContent -match '(?i)Ocp-Apim-Subscription-Key|api-key') -and
        $promptShieldContent.Contains('AgentIdentityAuthorizationScopes.ContentSafety', [StringComparison]::Ordinal)

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
        $oboExchangeCallCount -eq 4 -and
        $oboAppTokenCallCount -eq 1 -and
        $applicationContent -match '(?s)oboUserAssertion\s*=\s*await UserAuthorization\.GetTurnTokenAsync\s*\(\s*turnContext\s*,\s*handlers\.FoundryAuthHandlerName' -and
        $applicationContent.Contains('[AgentIdentityAuthorizationScopes.Foundry]', [StringComparison]::Ordinal) -and
        $applicationContent.Contains('[AgentIdentityAuthorizationScopes.ContentSafety]', [StringComparison]::Ordinal) -and
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

    $expectedInternalMcpToolNames = @(
        'search_korea_attractions',
        'get_korea_current_weather',
        'get_korea_weather_forecast',
        'get_korea_weather_alerts',
        'search_korea_accommodation',
        'convert_currency_with_rate',
        'get_exchange_rate',
        'convert_currency'
    )
    $schemaFingerprintCount = [regex]::Matches(
        $internalMcpOptionsContent,
        '"[A-F0-9]{64}"').Count
    $allExpectedToolNamesPresent = @($expectedInternalMcpToolNames | Where-Object {
        $internalMcpOptionsContent.Contains(('"' + $_ + '"'), [StringComparison]::Ordinal)
    }).Count -eq $expectedInternalMcpToolNames.Count
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
        @{ Name = 'Two protected host routes'; Valid = $dualFrontendRoutes },
        @{ Name = 'Frontend channel audience mapping'; Valid = $frontendChannelAudienceMapping }
    )) {
        $results.Add((New-StaValidationResult -Area 'Repository' -Check $sourceCheck.Name `
            -Status $(if ($sourceCheck.Valid) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($sourceCheck.Valid) { 'Required host boundary is present.' } else { 'Required host boundary is missing.' })))
    }

    foreach ($boundaryCheck in @(
        @{
            Name        = 'Prompt Shields fail-closed injection guard'
            Valid       = $promptShieldGuardPresent -and $promptShieldFailsClosed -and $promptShieldKeyless
            PassMessage = 'Prompt Shields screens the user prompt and tool results, rejects the turn on block or evaluation failure, and authenticates with a child Agent Identity token rather than an account key.'
            FailMessage = 'The Prompt Shields guard is missing, no longer screens both surfaces, fails open, or uses an account key.'
            Remediation = 'Restore PromptShieldGuard for both PromptShieldSurface values, keep the blocked and evaluation-failure branches returning from the turn, register CompositeToolContentEvaluator, and keep authentication on AgentIdentityAuthorizationScopes.ContentSafety.'
            Data        = @{
                GuardPresent = $promptShieldGuardPresent
                FailsClosed  = $promptShieldFailsClosed
                Keyless      = $promptShieldKeyless
            }
        },
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
        $results.Add((New-StaValidationResult -Area 'Repository' -Check $boundaryCheck.Name `
            -Status $(if ($boundaryCheck.Valid) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($boundaryCheck.Valid) { $boundaryCheck.PassMessage } else { $boundaryCheck.FailMessage }) `
            -Remediation $(if ($boundaryCheck.Valid) { '' } else { $boundaryCheck.Remediation }) `
            -Data $boundaryCheck.Data))
    }

    $readmePath = Join-Path $root 'README.md'
    $readmeFirstLine = if (Test-Path -LiteralPath $readmePath) { Get-Content -LiteralPath $readmePath -TotalCount 1 } else { '' }
    $readmeValid = $readmeFirstLine -eq '# Korea Tourist Expert Backend'
    $results.Add((New-StaValidationResult -Area 'Repository' -Check 'README identity' `
        -Status $(if ($readmeValid) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($readmeValid) { 'README describes the repository.' } else { 'README is stale or contains a merge artifact.' }) `
        -Remediation $(if ($readmeValid) { '' } else { 'Replace README.md with the Korea Tourist Expert Backend documentation.' })))

    if ($null -ne $milestone -and $milestone.Current.id -eq 'M0') {
        $implementationFiles = @(
            (Get-Item -LiteralPath (Join-Path $root 'Directory.Packages.props'))
            Get-StaFirstPartyFiles -Path (Join-Path $root 'server') -Extension @('.cs', '.csproj', '.props')
        )
        $implementationMarkers = @($implementationFiles | ForEach-Object {
            $relativePath = [IO.Path]::GetRelativePath($root, $_.FullName)
            Find-StaM0ImplementationMarker -Content (Get-Content -LiteralPath $_.FullName -Raw) -Source $relativePath
        })
        $m0Clean = $implementationMarkers.Count -eq 0
        $results.Add((New-StaValidationResult -Area 'Repository' -Check 'M0 onboarding boundary' `
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
            Find-StaForbiddenToolMutation `
                -Content (Get-Content -LiteralPath $_.FullName -Raw) `
                -Source ([IO.Path]::GetRelativePath($root, $_.FullName))
        })
    $results.Add((New-StaValidationResult -Area 'Repository' -Check 'Validation tool mutation safety' `
        -Status $(if ($toolMutationFindings.Count -eq 0) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($toolMutationFindings.Count -eq 0) { 'Validation tools contain no recognized cloud mutation command.' } else { 'Validation tools contain a recognized cloud mutation command.' }) `
        -Remediation $(if ($toolMutationFindings.Count -eq 0) { '' } else { 'Remove mutation commands from tools; keep setup and policy changes in approved milestone workflows.' }) `
        -Data @{ Findings = @($toolMutationFindings) }))

    $secretFindings = @(Find-StaPotentialSecrets -RepositoryRoot $root)
    $results.Add((New-StaValidationResult -Area 'Repository' -Check 'Secret hygiene' `
        -Status $(if ($secretFindings.Count -eq 0) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($secretFindings.Count -eq 0) { 'No obvious committed secret assignments were found.' } else { 'Potential secret values were found.' }) `
        -Remediation $(if ($secretFindings.Count -eq 0) { '' } else { 'Remove values and rotate any exposed credentials.' }) `
        -Data @{ Files = @($secretFindings) }))

    @($results)
}

function Test-StaAzureReadiness {
    [CmdletBinding()]
    param(
        [string] $RepositoryRoot = $script:DefaultRepositoryRoot,

        [switch] $Online,

        [string] $SubscriptionId = '',

        [string[]] $ResourceId = @()
    )

    $root = Resolve-StaRepositoryRoot -RepositoryRoot $RepositoryRoot
    $results = [System.Collections.Generic.List[object]]::new()
    $milestone = Get-StaMilestoneState -RepositoryRoot $root
    $azCommand = Get-Command az -ErrorAction SilentlyContinue
    if ($null -eq $azCommand) {
        return ,(New-StaValidationResult -Area 'Azure' -Check 'Azure CLI' -Status 'Fail' `
            -Message 'Azure CLI is not installed or is not on PATH.' `
            -Remediation 'Install Azure CLI before running Azure readiness checks.')
    }

    $results.Add((New-StaValidationResult -Area 'Azure' -Check 'Azure CLI' -Status 'Pass' `
        -Message 'Azure CLI is available.' -Data @{ Command = $azCommand.Source }))

    $endpoint = [Environment]::GetEnvironmentVariable('AgentHost__AzureOpenAIEndpoint', 'Process')
    $deployment = [Environment]::GetEnvironmentVariable('AgentHost__AzureOpenAIDeployment', 'Process')
    $mapsClientId = [Environment]::GetEnvironmentVariable('AzureMaps__ClientId', 'Process')

    if ([string]::IsNullOrWhiteSpace($endpoint)) {
        $results.Add((New-StaValidationResult -Area 'Azure' -Check 'Azure OpenAI endpoint' -Status 'Skip' `
            -Message 'AgentHost__AzureOpenAIEndpoint is not set in this process.' `
            -Remediation 'Set it only when validating a configured local environment.'))
    }
    else {
        $endpointUri = $null
        $validEndpoint = [Uri]::TryCreate($endpoint, [UriKind]::Absolute, [ref]$endpointUri) -and
            $endpointUri.Scheme -eq 'https'
        $results.Add((New-StaValidationResult -Area 'Azure' -Check 'Azure OpenAI endpoint' `
            -Status $(if ($validEndpoint) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($validEndpoint) { 'Configured endpoint is an absolute HTTPS URI.' } else { 'Configured endpoint is not an absolute HTTPS URI.' }) `
            -Remediation $(if ($validEndpoint) { '' } else { 'Set AgentHost__AzureOpenAIEndpoint to the Azure OpenAI HTTPS endpoint.' })))
    }

    $results.Add((New-StaValidationResult -Area 'Azure' -Check 'Azure OpenAI deployment' `
        -Status $(if ([string]::IsNullOrWhiteSpace($deployment)) { 'Skip' } else { 'Pass' }) `
        -Message $(if ([string]::IsNullOrWhiteSpace($deployment)) { 'AgentHost__AzureOpenAIDeployment is not set in this process.' } else { 'A deployment name is configured.' }) `
        -Remediation $(if ([string]::IsNullOrWhiteSpace($deployment)) { 'Set it only when validating a configured local environment.' } else { '' })))
    $results.Add((New-StaValidationResult -Area 'Azure' -Check 'Azure Maps client ID' `
        -Status $(if ([string]::IsNullOrWhiteSpace($mapsClientId)) { 'Skip' } else { 'Pass' }) `
        -Message $(if ([string]::IsNullOrWhiteSpace($mapsClientId)) { 'AzureMaps__ClientId is not set in this process.' } else { 'An Azure Maps account client ID is configured.' }) `
        -Remediation $(if ([string]::IsNullOrWhiteSpace($mapsClientId)) { 'Set it only when validating Azure Maps calls.' } else { '' })))

    if (-not $Online) {
        if (-not [string]::IsNullOrWhiteSpace($SubscriptionId) -or @($ResourceId).Count -gt 0) {
            $results.Add((New-StaValidationResult -Area 'Azure' -Check 'Online switch' -Status 'Fail' `
                -Message 'SubscriptionId and ResourceId checks require -Online.' `
                -Remediation 'Add -Online only when Azure subscription reads are intended.'))
        }
        $results.Add((New-StaValidationResult -Area 'Azure' -Check 'Azure account' -Status 'Skip' `
            -Message 'Online Azure checks were not requested. No Azure API call was made.'))
        return @($results)
    }

    if (-not $milestone.Current.allowsTenantReads) {
        $results.Add((New-StaValidationResult -Area 'Azure' -Check 'Milestone tenant-read authorization' -Status 'Fail' `
            -Message "Milestone '$($milestone.Current.id)' does not allow tenant reads." `
            -Remediation 'Do not run online validation until a reviewed milestone explicitly allows tenant reads.'))
        return @($results)
    }

    $accountInvocation = Invoke-StaNativeCommand -FilePath 'az' -ArgumentList @(
        'account', 'show', '--only-show-errors', '--output', 'json'
    ) -WorkingDirectory $root
    if ($accountInvocation.ExitCode -ne 0) {
        $results.Add((New-StaValidationResult -Area 'Azure' -Check 'Azure account' -Status 'Fail' `
            -Message 'Azure CLI does not have a usable signed-in account.' `
            -Remediation 'Run az login yourself, select the intended tenant/subscription, and retry.' `
            -Data @{ ExitCode = $accountInvocation.ExitCode; Output = $accountInvocation.Output }))
        return @($results)
    }

    try {
        $account = $accountInvocation.Output | ConvertFrom-Json -Depth 10
        $subscriptionMatches = [string]::IsNullOrWhiteSpace($SubscriptionId) -or
            $account.id -eq $SubscriptionId
        $results.Add((New-StaValidationResult -Area 'Azure' -Check 'Azure account' `
            -Status $(if ($subscriptionMatches) { 'Pass' } else { 'Fail' }) `
            -Message "Signed in to tenant '$($account.tenantId)' and subscription '$($account.id)'." `
            -Remediation $(if ($subscriptionMatches) { '' } else { 'Select the subscription requested by the validation command.' }) `
            -Data @{ SubscriptionId = $account.id; TenantId = $account.tenantId; Name = $account.name }))
    }
    catch {
        $results.Add((New-StaValidationResult -Area 'Azure' -Check 'Azure account response' -Status 'Fail' `
            -Message 'Azure CLI account output was not valid JSON.' -Remediation $_.Exception.Message))
    }

    foreach ($id in @($ResourceId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $resourceInvocation = Invoke-StaNativeCommand -FilePath 'az' -ArgumentList @(
            'resource', 'show', '--ids', $id, '--only-show-errors', '--output', 'json'
        ) -WorkingDirectory $root
        $results.Add((New-StaValidationResult -Area 'Azure' -Check "Resource: $id" `
            -Status $(if ($resourceInvocation.ExitCode -eq 0) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($resourceInvocation.ExitCode -eq 0) { 'Resource is visible to the current Azure identity.' } else { 'Resource could not be read.' }) `
            -Remediation $(if ($resourceInvocation.ExitCode -eq 0) { '' } else { 'Verify the resource ID, tenant, subscription, and read access.' }) `
            -Data @{ ExitCode = $resourceInvocation.ExitCode }))
    }

    @($results)
}

function Test-StaPurviewMiddlewareOrder {
    [CmdletBinding()]
    param([AllowEmptyString()][string] $Source)

    $withoutComments = [regex]::Replace($Source, '(?s:/\*.*?\*/)|(?m://.*$)', '')
    $withoutComments -match '(?s)\.WithPurview\s*\(.*?\.UseFunctionInvocation\s*\(.*?\.UseOpenTelemetry\s*\('
}

function Get-StaPurviewEnforcementResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int] $StatusCode,

        [AllowEmptyString()]
        [string] $Content = '',

        [switch] $ExpectBlock
    )

    if ($StatusCode -notin @(200, 202, 204)) {
        return New-StaValidationResult -Area 'Purview' -Check 'processContent enforcement' -Status 'Fail' `
            -Message "HTTP $StatusCode is not a successful processContent response." `
            -Remediation 'Resolve connectivity and authorization before evaluating enforcement.' `
            -Data @{ StatusCode = $StatusCode; EnforcementEvidence = $false }
    }

    if ([string]::IsNullOrWhiteSpace($Content)) {
        if ($StatusCode -eq 200) {
            return New-StaValidationResult -Area 'Purview' -Check 'processContent enforcement' -Status 'Fail' `
                -Message 'HTTP 200 returned no response body, so no enforcement evidence is available.' `
                -Remediation 'Capture the client request ID and investigate why a completed evaluation omitted its response.' `
                -Data @{ StatusCode = $StatusCode; EnforcementEvidence = $false }
        }

        return New-StaValidationResult -Area 'Purview' -Check 'processContent enforcement' `
            -Status $(if ($ExpectBlock) { 'Fail' } else { 'Skip' }) `
            -Message "HTTP $StatusCode confirms acceptance but provides no synchronous enforcement evidence." `
            -Remediation $(if ($ExpectBlock) { 'Use a completed 200 response or tenant-side evidence before claiming blocking enforcement.' } else { '' }) `
            -Data @{ StatusCode = $StatusCode; EnforcementEvidence = $false }
    }

    try {
        $response = $Content | ConvertFrom-Json -Depth 30
    }
    catch {
        return New-StaValidationResult -Area 'Purview' -Check 'processContent enforcement' -Status 'Fail' `
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
    New-StaValidationResult -Area 'Purview' -Check 'processContent enforcement' `
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

function Test-StaPurviewReadiness {
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

        [string] $ProbeText = 'Korea Tourist Expert synthetic Purview validation probe.',

        [switch] $ExpectBlock,

        [ValidateRange(1, 120)]
        [int] $ProbeTimeoutSeconds = 30
    )

    $root = Resolve-StaRepositoryRoot -RepositoryRoot $RepositoryRoot
    $milestone = Get-StaMilestoneState -RepositoryRoot $root
    $results = [System.Collections.Generic.List[object]]::new()
    $purviewVersion = Get-StaPackageVersion -PackageName 'Microsoft.Agents.AI.Purview' -RepositoryRoot $root
    $agentFrameworkVersion = Get-StaPackageVersion -PackageName 'Microsoft.Agents.AI' -RepositoryRoot $root
    $azureIdentityVersion = Get-StaPackageVersion -PackageName 'Azure.Identity' -RepositoryRoot $root
    $extensionsAiVersion = Get-StaPackageVersion -PackageName 'Microsoft.Extensions.AI' -RepositoryRoot $root
    if ([string]::IsNullOrWhiteSpace($extensionsAiVersion)) {
        $extensionsAiVersion = Get-StaPackageVersion -PackageName 'Microsoft.Extensions.AI.OpenAI' -RepositoryRoot $root
    }
    $isImplemented = -not [string]::IsNullOrWhiteSpace($purviewVersion)
    $purviewAuthorized = $milestone.Current.id -ne 'M0'

    $results.Add((New-StaValidationResult -Area 'Purview' -Check 'Milestone authorization' `
        -Status $(if ($purviewAuthorized) { 'Pass' } else { 'Skip' }) `
        -Message $(if ($purviewAuthorized) { "$($milestone.Current.id) is active, so Purview readiness may be evaluated." } else { 'Purview implementation is deferred during foundation milestone M0.' }) `
        -Remediation $(if ($purviewAuthorized) { '' } else { 'Do not install or wire Purview until a post-foundation milestone is explicitly activated.' })))

    $packageStatus = if ($isImplemented) { 'Pass' } elseif ($RequireImplemented) { 'Fail' } else { 'Skip' }
    $results.Add((New-StaValidationResult -Area 'Purview' -Check 'Agent Framework Purview package' `
        -Status $packageStatus `
        -Message $(if ($isImplemented) { "Microsoft.Agents.AI.Purview is pinned to $purviewVersion." } else { 'Microsoft.Agents.AI.Purview is not installed, as expected during M0.' }) `
        -Remediation $(if ($RequireImplemented -and -not $isImplemented) { 'Activate the milestone that owns Purview implementation and perform the coordinated dependency upgrade before adding middleware.' } else { '' })))

    if ($isImplemented) {
        $agentFrameworkParsed = ConvertTo-StaVersion -Value $agentFrameworkVersion
        $azureIdentityParsed = ConvertTo-StaVersion -Value $azureIdentityVersion
        $extensionsAiParsed = ConvertTo-StaVersion -Value $extensionsAiVersion
        foreach ($dependency in @(
            @{ Name = 'Microsoft.Agents.AI'; Current = $agentFrameworkParsed; Minimum = [version]'1.17.0' },
            @{ Name = 'Azure.Identity'; Current = $azureIdentityParsed; Minimum = [version]'1.21.0' },
            @{ Name = 'Microsoft.Extensions.AI'; Current = $extensionsAiParsed; Minimum = [version]'10.7.0' }
        )) {
            $valid = $null -ne $dependency.Current -and $dependency.Current -ge $dependency.Minimum
            $results.Add((New-StaValidationResult -Area 'Purview' -Check "$($dependency.Name) compatibility" `
                -Status $(if ($valid) { 'Pass' } else { 'Fail' }) `
                -Message $(if ($valid) { "Version $($dependency.Current) meets the Purview minimum." } else { "Version '$($dependency.Current)' is below the Purview minimum $($dependency.Minimum)." }) `
                -Remediation $(if ($valid) { '' } else { 'Upgrade the Microsoft dependency train together and run the full build/test gate.' })))
        }

        $hostSources = (Get-StaFirstPartyFiles `
            -Path (Join-Path $root 'server\agent-host') `
            -Extension @('.cs') |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
        $hostSources = [regex]::Replace($hostSources, '(?s:/\*.*?\*/)|(?m://.*$)', '')
        $purviewWired = $hostSources -match '\.WithPurview\s*\('
        $failClosed = $hostSources -match 'IgnoreExceptions\s*=\s*false'
        $userIdentity = $hostSources -match '\.SetUserId\s*\('
        $sensitiveTelemetryDisabled = $hostSources -match 'EnableSensitiveData\s*=\s*false'
        $middlewareOrder = Test-StaPurviewMiddlewareOrder -Source $hostSources
        foreach ($codeCheck in @(
            @{ Name = 'Purview middleware'; Valid = $purviewWired; Message = 'WithPurview is wired in the host.' },
            @{ Name = 'Fail-closed policy'; Valid = $failClosed; Message = 'Purview IgnoreExceptions is explicitly false.' },
            @{ Name = 'User policy identity'; Valid = $userIdentity; Message = 'Messages are associated with a Purview user ID.' },
            @{ Name = 'Sensitive telemetry disabled'; Valid = $sensitiveTelemetryDisabled; Message = 'Sensitive telemetry capture is explicitly disabled.' },
            @{ Name = 'Middleware order'; Valid = $middlewareOrder; Message = 'Purview wraps function invocation, which wraps OpenTelemetry.' }
        )) {
            $results.Add((New-StaValidationResult -Area 'Purview' -Check $codeCheck.Name `
                -Status $(if ($codeCheck.Valid) { 'Pass' } else { 'Fail' }) `
                -Message $(if ($codeCheck.Valid) { $codeCheck.Message } else { "$($codeCheck.Name) evidence is missing." })))
        }

        $purviewTestDirectory = Join-Path ([IO.Path]::GetTempPath()) "korea-expert-purview-tests-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $purviewTestDirectory -Force | Out-Null
        $priorRepositoryRoot = [Environment]::GetEnvironmentVariable(
            'KOREA_EXPERT_REPOSITORY_ROOT',
            [EnvironmentVariableTarget]::Process)
        try {
            [Environment]::SetEnvironmentVariable(
                'KOREA_EXPERT_REPOSITORY_ROOT',
                $root,
                [EnvironmentVariableTarget]::Process)
            $purviewTestProject = Join-Path $root 'tests\KoreaExpert.AgentHost.Tests\KoreaExpert.AgentHost.Tests.csproj'
            $purviewTests = Invoke-StaNativeCommand -FilePath 'dotnet' -ArgumentList @(
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
            $results.Add((New-StaValidationResult -Area 'Purview' -Check 'Executable Purview behavior tests' `
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
                'KOREA_EXPERT_REPOSITORY_ROOT',
                $priorRepositoryRoot,
                [EnvironmentVariableTarget]::Process)
            Remove-Item -LiteralPath $purviewTestDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (($CheckTenantPolicy -or $ProbePolicy) -and -not $Online) {
        $results.Add((New-StaValidationResult -Area 'Purview' -Check 'Online switch' -Status 'Fail' `
            -Message 'Tenant policy checks and probes require -Online.' `
            -Remediation 'Add -Online only when tenant reads are intended.'))
        return @($results)
    }
    if ($Online -and -not $milestone.Current.allowsTenantReads) {
        $results.Add((New-StaValidationResult -Area 'Purview' -Check 'Milestone tenant-read authorization' -Status 'Fail' `
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
            $results.Add((New-StaValidationResult -Area 'Purview' -Check 'DSPM collection policy' -Status 'Fail' `
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
                $results.Add((New-StaValidationResult -Area 'Purview' -Check 'DSPM collection policy' `
                    -Status $(if ($hasRequiredCollectionPolicy) { 'Pass' } else { 'Fail' }) `
                    -Message $(if ($hasRequiredCollectionPolicy) { 'An enabled policy uses the Application enforcement plane for upload and download text.' } else { 'No enabled policy shows the required Application, UploadText, and DownloadText configuration.' }) `
                    -Remediation $(if ($hasRequiredCollectionPolicy) { '' } else { 'Ask a Purview administrator to review the DSPM for AI collection policies.' }) `
                    -Data $purviewTenantContext))
            }
            catch {
                $results.Add((New-StaValidationResult -Area 'Purview' -Check 'DSPM collection policy' -Status 'Fail' `
                    -Message 'The DSPM collection policy could not be read.' -Remediation $_.Exception.Message))
            }
        }
    }

    if ($ProbePolicy) {
        $token = [Environment]::GetEnvironmentVariable($AccessTokenEnvironmentVariable, 'Process')
        if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($UserId) -or [string]::IsNullOrWhiteSpace($ApplicationId)) {
            $results.Add((New-StaValidationResult -Area 'Purview' -Check 'processContent probe' -Status 'Fail' `
                -Message 'The probe requires UserId, ApplicationId, and an access token in the named environment variable.' `
                -Remediation "Grant Content.Process.User or Content.Process.All, set $AccessTokenEnvironmentVariable in your shell, and pass non-secret IDs."))
        }
        else {
            $tokenContext = Get-StaJwtContext -Token $token
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
                name            = 'Korea Tourist Expert validation probe'
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
                    name          = 'Korea Tourist Expert'
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
                        name = 'Korea Tourist Expert'
                        version = '1.0'
                        applicationLocation = [ordered]@{
                            '@odata.type' = 'microsoft.graph.policyLocationApplication'
                            value = $ApplicationId
                        }
                    }
                    integratedAppMetadata = [ordered]@{
                        name = 'Korea Tourist Expert validation tools'
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
                $results.Add((New-StaValidationResult -Area 'Purview' -Check 'processContent connectivity' `
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
                    $results.Add((Get-StaPurviewEnforcementResult `
                        -StatusCode $statusCode `
                        -Content $webResponse.Content `
                        -ExpectBlock:$ExpectBlock))
                }
            }
            catch {
                $results.Add((New-StaValidationResult -Area 'Purview' -Check 'processContent connectivity' -Status 'Fail' `
                    -Message 'Microsoft Graph processContent failed.' `
                    -Remediation 'Verify Content.Process permissions, user/application IDs, licensing, policy configuration, and token validity.' `
                    -Data @{ Error = $_.Exception.Message }))
            }
        }
    }

    @($results)
}

function Get-StaFreeTcpPort {
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

function Get-StaLogTail {
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

function Wait-StaHealthEndpoint {
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

function Stop-StaProcessTree {
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
            $taskKill = Invoke-StaNativeCommand -FilePath 'taskkill.exe' -ArgumentList @(
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

function Invoke-StaLocalCi {
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

    $root = Resolve-StaRepositoryRoot -RepositoryRoot $RepositoryRoot
    $results = [System.Collections.Generic.List[object]]::new()
    $solutionPath = Join-Path $root 'KoreaExpertAgent.slnx'
    $runDirectory = Join-Path ([IO.Path]::GetTempPath()) "korea-expert-ci-$([guid]::NewGuid())"
    $artifactsDirectory = Join-Path $runDirectory 'artifacts'
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

    if (-not $SkipToolsSelfTest) {
        $selfTest = Invoke-StaNativeCommand -FilePath 'pwsh' -ArgumentList @(
            '-NoLogo', '-NoProfile', '-File',
            (Join-Path $root 'tools\tests\Invoke-ToolsSelfTest.ps1'),
            '-RepositoryRoot', $root
        ) -WorkingDirectory $root
        $results.Add((New-StaValidationResult -Area 'LocalCI' -Check 'Tools self-test' `
            -Status $(if ($selfTest.ExitCode -eq 0) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($selfTest.ExitCode -eq 0) { 'PowerShell validation tools passed their self-tests.' } else { 'PowerShell validation tools failed their self-tests.' }) `
            -Remediation $(if ($selfTest.ExitCode -eq 0) { '' } else { $selfTest.Output }) `
            -Data @{ ExitCode = $selfTest.ExitCode }))
    }

    if (-not $SkipBuild) {
        $build = Invoke-StaNativeCommand -FilePath 'dotnet' -ArgumentList @(
            'build', $solutionPath,
            '--configuration', $Configuration,
            '--artifacts-path', $artifactsDirectory,
            '--nologo'
        ) -WorkingDirectory $root
        $results.Add((New-StaValidationResult -Area 'LocalCI' -Check 'Solution build' `
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
            'KOREA_EXPERT_REPOSITORY_ROOT',
            [EnvironmentVariableTarget]::Process)
        try {
            [Environment]::SetEnvironmentVariable(
                'KOREA_EXPERT_REPOSITORY_ROOT',
                $root,
                [EnvironmentVariableTarget]::Process)
            $tests = Invoke-StaNativeCommand -FilePath 'dotnet' -ArgumentList $testArguments -WorkingDirectory $root
        }
        finally {
            [Environment]::SetEnvironmentVariable(
                'KOREA_EXPERT_REPOSITORY_ROOT',
                $priorRepositoryRoot,
                [EnvironmentVariableTarget]::Process)
        }
        $results.Add((New-StaValidationResult -Area 'LocalCI' -Check 'Solution tests' `
            -Status $(if ($tests.ExitCode -eq 0) { 'Pass' } else { 'Fail' }) `
            -Message $(if ($tests.ExitCode -eq 0) { "$Configuration solution tests passed." } else { "$Configuration solution tests failed." }) `
            -Remediation $(if ($tests.ExitCode -eq 0) { '' } else { $tests.Output }) `
            -Data @{ ExitCode = $tests.ExitCode; Configuration = $Configuration }))
    }
    elseif (-not $SkipTests) {
        $results.Add((New-StaValidationResult -Area 'LocalCI' -Check 'Solution tests' -Status 'Skip' `
            -Message 'Tests were skipped because the solution build failed.'))
    }

    if ($SkipHealth -or $buildFailed) {
        if (-not $SkipHealth) {
            $results.Add((New-StaValidationResult -Area 'LocalCI' -Check 'Service health' -Status 'Skip' `
                -Message 'Service health was skipped because the solution build failed.'))
        }
        Remove-Item -LiteralPath $runDirectory -Recurse -Force -ErrorAction SilentlyContinue
        return @($results)
    }

    $services = @(
        @{
            Name       = 'Agent host'
            ProjectDir = 'server\agent-host\KoreaExpert.AgentHost'
            Assembly   = 'KoreaExpert.AgentHost.dll'
            HealthChecks = @(
                @{ Name = 'Agent host health'; Path = '/api/health'; ExpectedStatus = @('healthy') },
                @{ Name = 'Agent host liveness'; Path = '/api/health/live'; ExpectedStatus = @('healthy') },
                @{ Name = 'Agent host readiness'; Path = '/api/health/ready'; ExpectedStatus = @('healthy', 'degraded') }
            )
        },
        @{
            Name       = 'Attractions MCP'
            ProjectDir = 'server\mcp\attractions\KoreaExpert.Mcp.Attractions'
            Assembly   = 'KoreaExpert.Mcp.Attractions.dll'
            HealthChecks = @(@{ Name = 'Attractions MCP health'; Path = '/health'; ExpectedStatus = @('healthy') })
        },
        @{
            Name       = 'Weather MCP'
            ProjectDir = 'server\mcp\weather\KoreaExpert.Mcp.Weather'
            Assembly   = 'KoreaExpert.Mcp.Weather.dll'
            HealthChecks = @(@{ Name = 'Weather MCP health'; Path = '/health'; ExpectedStatus = @('healthy') })
        },
        @{
            Name       = 'Accommodation MCP'
            ProjectDir = 'server\mcp\accommodation\KoreaExpert.Mcp.Accommodation'
            Assembly   = 'KoreaExpert.Mcp.Accommodation.dll'
            HealthChecks = @(@{ Name = 'Accommodation MCP health'; Path = '/health'; ExpectedStatus = @('healthy') })
        },
        @{
            Name       = 'Currency MCP'
            ProjectDir = 'server\mcp\currency\KoreaExpert.Mcp.Currency'
            Assembly   = 'KoreaExpert.Mcp.Currency.dll'
            HealthChecks = @(@{ Name = 'Currency MCP health'; Path = '/health'; ExpectedStatus = @('healthy') })
        }
    )

    $processes = [System.Collections.Generic.List[object]]::new()
    $cleanupFailures = [System.Collections.Generic.List[string]]::new()
    $originalEnvironment = [Environment]::GetEnvironmentVariable('ASPNETCORE_ENVIRONMENT', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('ASPNETCORE_ENVIRONMENT', 'Development', 'Process')
        foreach ($service in $services) {
            $projectDirectory = Join-Path $root $service.ProjectDir
            $projectName = @($service.ProjectDir -split '[\\/]')[-1]
            $assemblyPath = Join-Path $artifactsDirectory "bin\$projectName\$($Configuration.ToLowerInvariant())\$($service.Assembly)"
            if (-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) {
                $results.Add((New-StaValidationResult -Area 'LocalCI' -Check "$($service.Name) health" -Status 'Fail' `
                    -Message "Compiled assembly is missing: $assemblyPath" `
                    -Remediation 'Run the solution build before health validation.'))
                continue
            }

            $port = Get-StaFreeTcpPort
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
                $results.Add((New-StaValidationResult -Area 'LocalCI' -Check "$($service.Name) health" -Status 'Fail' `
                    -Message 'Service process could not be started.' -Remediation $_.Exception.Message))
            }
        }

        foreach ($entry in $processes) {
            foreach ($healthCheck in $entry.Service.HealthChecks) {
                $healthUri = [Uri]::new("$($entry.BaseUri)$($healthCheck.Path)")
                $health = Wait-StaHealthEndpoint `
                    -Uri $healthUri `
                    -Process $entry.Process `
                    -TimeoutSeconds $HealthTimeoutSeconds `
                    -ExpectedStatus $healthCheck.ExpectedStatus
                $logTail = if ($health.Healthy) {
                    ''
                }
                else {
                    Get-StaLogTail `
                        -StandardOutputPath $entry.StandardOutputPath `
                        -StandardErrorPath $entry.StandardErrorPath
                }
                $statusValue = if ($health.Healthy) {
                    ($health.Body | ConvertFrom-Json -Depth 10).status
                }
                else {
                    ''
                }
                $results.Add((New-StaValidationResult -Area 'LocalCI' -Check $healthCheck.Name `
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
                if (-not (Stop-StaProcessTree -Process $entry.Process)) {
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

    $results.Add((New-StaValidationResult -Area 'LocalCI' -Check 'Process cleanup' `
        -Status $(if ($cleanupFailures.Count -eq 0) { 'Pass' } else { 'Fail' }) `
        -Message $(if ($cleanupFailures.Count -eq 0) { 'All temporary host and MCP processes were terminated.' } else { 'One or more temporary service processes could not be terminated.' }) `
        -Remediation $(if ($cleanupFailures.Count -eq 0) { '' } else { 'Stop the reported processes and remove temporary directories before rerunning local CI.' }) `
        -Data @{ CleanupFailures = @($cleanupFailures); ProcessCount = $processes.Count }))

    @($results)
}

function Write-StaValidationResults {
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

function Get-StaValidationExitCode {
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
    'ConvertTo-StaVersion',
    'Find-StaPotentialSecrets',
    'Find-StaForbiddenToolMutation',
    'Find-StaM0ImplementationMarker',
    'Get-StaMilestoneState',
    'Get-StaPackageVersion',
    'Get-StaFirstPartyFiles',
    'Get-StaFreeTcpPort',
    'Get-StaPurviewEnforcementResult',
    'Get-StaValidationExitCode',
    'Invoke-StaValidationSafely',
    'Stop-StaProcessTree',
    'New-StaValidationResult',
    'Resolve-StaRepositoryRoot',
    'Test-StaPrerequisites',
    'Test-StaAzureReadiness',
    'Test-StaPurviewReadiness',
    'Test-StaPurviewMiddlewareOrder',
    'Test-StaRepositoryConfiguration',
    'Invoke-StaLocalCi',
    'Write-StaValidationResults'
)
