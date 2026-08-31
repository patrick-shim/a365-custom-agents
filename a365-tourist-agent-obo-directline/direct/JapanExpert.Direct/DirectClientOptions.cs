using System.Globalization;

namespace JapanExpert.Direct;

public sealed class DirectClientOptions
{
    public const string DefaultSecretEnvironmentVariable =
        "JAPAN_EXPERT_DIRECT_LINE_SECRET";

    public const string EndpointEnvironmentVariable =
        "JAPAN_EXPERT_DIRECT_LINE_ENDPOINT";

    private DirectClientOptions(
        Uri endpoint,
        string secret,
        string secretEnvironmentVariable,
        string userId,
        string userName,
        bool launchBrowser,
        string? initialMessage,
        string? sitListPath,
        TimeSpan sitInterval,
        TimeSpan pollInterval,
        TimeSpan responseTimeout)
    {
        Endpoint = endpoint;
        Secret = secret;
        SecretEnvironmentVariable = secretEnvironmentVariable;
        UserId = userId;
        UserName = userName;
        LaunchBrowser = launchBrowser;
        InitialMessage = initialMessage;
        SitListPath = sitListPath;
        SitInterval = sitInterval;
        PollInterval = pollInterval;
        ResponseTimeout = responseTimeout;
    }

    public Uri Endpoint { get; }

    public string Secret { get; }

    public string SecretEnvironmentVariable { get; }

    public string UserId { get; }

    public string UserName { get; }

    public bool LaunchBrowser { get; }

    public string? InitialMessage { get; }

    public string? SitListPath { get; }

    public TimeSpan SitInterval { get; }

    public TimeSpan PollInterval { get; }

    public TimeSpan ResponseTimeout { get; }

    public static DirectClientOptions Parse(
        IReadOnlyList<string> args,
        Func<string, string?>? readEnvironmentVariable = null)
    {
        ArgumentNullException.ThrowIfNull(args);
        readEnvironmentVariable ??= Environment.GetEnvironmentVariable;

        var endpointValue = readEnvironmentVariable(EndpointEnvironmentVariable)
            ?? DirectLineClient.DefaultEndpoint.AbsoluteUri;
        var secretEnvironmentVariable = DefaultSecretEnvironmentVariable;
        var userId = "dl_japan_expert_cli";
        var userName = "Japan Expert CLI";
        var launchBrowser = true;
        string? initialMessage = null;
        var useSitList = false;
        string? sitListPath = null;
        var intervalSpecified = false;
        var sitInterval = TimeSpan.FromSeconds(5);
        var pollInterval = TimeSpan.FromSeconds(1);
        var responseTimeout = TimeSpan.FromSeconds(90);

        for (var index = 0; index < args.Count; index++)
        {
            switch (args[index])
            {
                case "--endpoint":
                    endpointValue = ReadValue(args, ref index);
                    break;
                case "--secret-env":
                    secretEnvironmentVariable = ReadValue(args, ref index);
                    break;
                case "--user-id":
                    userId = ReadValue(args, ref index);
                    break;
                case "--user-name":
                    userName = ReadValue(args, ref index);
                    break;
                case "--message":
                    initialMessage = ReadValue(args, ref index);
                    break;
                case "--sit-list":
                    useSitList = true;
                    break;
                case "--sit-file":
                    sitListPath = ReadValue(args, ref index);
                    break;
                case "--interval":
                    intervalSpecified = true;
                    sitInterval = TimeSpan.FromSeconds(ParseInteger(
                        ReadValue(args, ref index),
                        "--interval",
                        minimum: 1,
                        maximum: 86_400));
                    break;
                case "--poll-ms":
                    pollInterval = TimeSpan.FromMilliseconds(ParseInteger(
                        ReadValue(args, ref index),
                        "--poll-ms",
                        minimum: 1,
                        maximum: 30_000));
                    break;
                case "--timeout-seconds":
                    responseTimeout = TimeSpan.FromSeconds(ParseInteger(
                        ReadValue(args, ref index),
                        "--timeout-seconds",
                        minimum: 1,
                        maximum: 3_600));
                    break;
                case "--no-browser":
                    launchBrowser = false;
                    break;
                default:
                    throw new DirectClientOptionsException(
                        $"Unknown option '{args[index]}'. Use --help for usage.");
            }
        }

        if (!Uri.TryCreate(endpointValue, UriKind.Absolute, out var endpoint)
            || !DirectLineClient.IsTrustedEndpoint(endpoint))
        {
            throw new DirectClientOptionsException(
                "--endpoint must use HTTPS, except for an explicit loopback development endpoint.");
        }

        var secret = readEnvironmentVariable(secretEnvironmentVariable);
        if (string.IsNullOrWhiteSpace(secret))
        {
            throw new DirectClientOptionsException(
                $"Set the {secretEnvironmentVariable} environment variable before starting the client.");
        }

        if (string.IsNullOrWhiteSpace(userId) || string.IsNullOrWhiteSpace(userName))
        {
            throw new DirectClientOptionsException("Direct Line user ID and name cannot be empty.");
        }

        if (useSitList && !string.IsNullOrWhiteSpace(initialMessage))
        {
            throw new DirectClientOptionsException(
                "--sit-list and --message cannot be used together.");
        }

        if (!useSitList && (sitListPath is not null || intervalSpecified))
        {
            throw new DirectClientOptionsException(
                "--sit-file and --interval require --sit-list.");
        }

        if (useSitList)
        {
            sitListPath = Path.GetFullPath(
                sitListPath ?? Path.Combine("direct", "sensitive-information-type-test.json"));
        }

        return new DirectClientOptions(
            endpoint,
            secret,
            secretEnvironmentVariable,
            userId,
            userName,
            launchBrowser,
            initialMessage,
            sitListPath,
            sitInterval,
            pollInterval,
            responseTimeout);
    }

    public static string GetHelpText() =>
        $$"""
        Japan Expert Direct Line client

        Usage:
          dotnet run --project direct/JapanExpert.Direct -- [options]

        Required environment:
          {{DefaultSecretEnvironmentVariable}}   Direct Line channel secret. Never pass it on the command line.

        Options:
          --endpoint <url>          Direct Line v3 base URL.
          --secret-env <name>       Read the channel secret from another environment variable.
          --user-id <id>            Stable Direct Line user ID (default: dl_japan_expert_cli).
          --user-name <name>        Display name sent to the bot.
          --message <text>          Send one message and exit after the reply.
          --sit-list                Send every prompt from the synthetic SIT JSON list.
          --sit-file <path>         Override direct/sensitive-information-type-test.json.
          --interval <seconds>      Delay between SIT prompts (default: 5; requires --sit-list).
          --poll-ms <number>        Activity polling interval (default: 1000).
          --timeout-seconds <n>     Reply timeout after each send or sign-in (default: 90).
          --no-browser              Print the OAuth URL without launching a browser.
          --help                    Show this help.

        Interactive commands:
          /help                     Show interactive commands.
          /exit                     End the conversation.
        """;

    private static string ReadValue(IReadOnlyList<string> args, ref int index)
    {
        if (++index >= args.Count || string.IsNullOrWhiteSpace(args[index]))
        {
            throw new DirectClientOptionsException(
                $"Option '{args[index - 1]}' requires a value.");
        }

        return args[index];
    }

    private static int ParseInteger(
        string value,
        string option,
        int minimum,
        int maximum)
    {
        if (!int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var parsed)
            || parsed < minimum
            || parsed > maximum)
        {
            throw new DirectClientOptionsException(
                $"{option} must be an integer from {minimum} through {maximum}.");
        }

        return parsed;
    }
}

public sealed class DirectClientOptionsException(string message) : Exception(message);
