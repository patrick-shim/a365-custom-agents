using Azure.AI.OpenAI;
using Azure.Core;
using Azure.Identity;
using Microsoft.Agents.AI.Purview;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Options;

namespace SeoulTourist.AgentHost;

public sealed class AgentChatClientFactory : IDisposable
{
    private readonly AgentHostOptions _agentHostOptions;
    private readonly PurviewDlpOptions _purviewOptions;
    private readonly InternalMcpOptions _internalMcpOptions;
    private readonly AgentIdentityTokenContext _tokenContext;
    private readonly PurviewAgentIdentityTokenCredential _purviewCredential;
    private readonly ToolContentProtector _toolContentProtector;
    private readonly PurviewApplicationLocationResolver _purviewApplicationLocation;
    private readonly ILoggerFactory _loggerFactory;
    private readonly TokenCredential? _localCredential;
    private readonly AgentChatClientRegistry _clientRegistry;

    public AgentChatClientFactory(
        IOptions<AgentHostOptions> agentHostOptions,
        IOptions<PurviewDlpOptions> purviewOptions,
        IOptions<InternalMcpOptions> internalMcpOptions,
        AgentIdentityTokenContext tokenContext,
        PurviewAgentIdentityTokenCredential purviewCredential,
        ToolContentProtector toolContentProtector,
        PurviewApplicationLocationResolver purviewApplicationLocation,
        ILoggerFactory loggerFactory,
        IHostEnvironment environment)
    {
        _agentHostOptions = agentHostOptions.Value;
        _purviewOptions = purviewOptions.Value;
        _internalMcpOptions = internalMcpOptions.Value;
        _tokenContext = tokenContext;
        _purviewCredential = purviewCredential;
        _toolContentProtector = toolContentProtector;
        _purviewApplicationLocation = purviewApplicationLocation;
        _loggerFactory = loggerFactory;

        if (environment.IsDevelopment() || environment.IsEnvironment("Playground"))
        {
            _localCredential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
            {
                ExcludeManagedIdentityCredential = true
            });
        }

        _clientRegistry = new AgentChatClientRegistry(CreateClient);
    }

    public IChatClient Create()
    {
        var applicationId = _purviewOptions.Enabled
            ? _purviewApplicationLocation.Resolve()
            : string.Empty;
        return _clientRegistry.Create(applicationId);
    }

    public void Dispose() => _clientRegistry.Dispose();

    private IChatClient CreateClient(string applicationId)
    {
        TokenCredential credential = _tokenContext.Current is not null
            ? new AgentIdentityTokenCredential(_tokenContext)
            : _localCredential
                ?? throw new InvalidOperationException(
                    "An Agent Identity token context is required outside local development.");

        var chatClientBuilder = new AzureOpenAIClient(
                new Uri(_agentHostOptions.AzureOpenAIEndpoint),
                credential)
            .GetChatClient(_agentHostOptions.AzureOpenAIDeployment)
            .AsIChatClient()
            .AsBuilder();

        if (_purviewOptions.Enabled)
        {
            var purviewCredential = _tokenContext.Current is not null
                ? _purviewCredential
                : credential;
            chatClientBuilder.WithPurview(
                purviewCredential,
                PurviewSettingsFactory.Create(
                    _purviewOptions,
                    applicationId),
                _loggerFactory.CreateLogger("PurviewDlp"));
        }

        // Purview protects the user prompt and final answer. Tool arguments and results are
        // independently protected before function execution by ToolContentProtector.
        chatClientBuilder.UseFunctionInvocation(
            _loggerFactory,
            functionInvocation =>
            {
                functionInvocation.IncludeDetailedErrors = false;
                functionInvocation.MaximumConsecutiveErrorsPerRequest = 0;
                if (_internalMcpOptions.Enabled)
                {
                    functionInvocation.FunctionInvoker = _toolContentProtector.InvokeAsync;
                }
            });

        // Telemetry is innermost and may never capture raw prompts, responses, or tool values.
        chatClientBuilder.UseOpenTelemetry(
            sourceName: null,
            configure: instrumentation => instrumentation.EnableSensitiveData = false);

        return chatClientBuilder.Build();
    }
}

internal sealed class AgentChatClientRegistry(Func<string, IChatClient> clientFactory) : IDisposable
{
    private readonly List<IChatClient> _clients = [];
    private readonly object _sync = new();
    private bool _disposed;

    public IChatClient Create(string applicationId)
    {
        ArgumentNullException.ThrowIfNull(applicationId);

        lock (_sync)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            var client = clientFactory(applicationId);
            _clients.Add(client);
            return client;
        }
    }

    public void Dispose()
    {
        lock (_sync)
        {
            if (_disposed)
            {
                return;
            }

            foreach (var client in _clients)
            {
                client.Dispose();
            }

            _clients.Clear();
            _disposed = true;
        }
    }
}
