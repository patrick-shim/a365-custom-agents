using System.ComponentModel;
using System.Diagnostics;

namespace JapanExpert.Direct;

public sealed class ConsoleConversation
{
    private readonly DirectLineClient _client;
    private readonly DirectClientOptions _options;
    private readonly TextReader _input;
    private readonly TextWriter _output;
    private readonly Action<Uri> _launchBrowser;
    private readonly Func<TimeSpan, CancellationToken, Task> _delay;
    private readonly HashSet<string> _seenActivityIds = new(StringComparer.Ordinal);

    public ConsoleConversation(
        DirectLineClient client,
        DirectClientOptions options,
        TextReader? input = null,
        TextWriter? output = null,
        Action<Uri>? launchBrowser = null,
        Func<TimeSpan, CancellationToken, Task>? delay = null)
    {
        ArgumentNullException.ThrowIfNull(client);
        ArgumentNullException.ThrowIfNull(options);
        _client = client;
        _options = options;
        _input = input ?? Console.In;
        _output = output ?? Console.Out;
        _launchBrowser = launchBrowser ?? LaunchBrowser;
        _delay = delay ?? Task.Delay;
    }

    public async Task RunAsync(CancellationToken cancellationToken = default)
    {
        var session = await _client.StartConversationAsync(
            _options.Secret,
            _options.UserId,
            _options.UserName,
            cancellationToken);
        await _output.WriteLineAsync(
            $"Connected to Direct Line conversation {session.ConversationId}.");

        if (!string.IsNullOrWhiteSpace(_options.InitialMessage))
        {
            await SendAndReceiveAsync(session, _options.InitialMessage, cancellationToken);
            return;
        }

        if (!string.IsNullOrWhiteSpace(_options.SitListPath))
        {
            await RunSitListAsync(session, cancellationToken);
            return;
        }

        await _output.WriteLineAsync("Type /help for commands or /exit to quit.");
        while (!cancellationToken.IsCancellationRequested)
        {
            await _output.WriteAsync("you> ");
            await _output.FlushAsync(cancellationToken);
            var input = await _input.ReadLineAsync(cancellationToken);
            if (input is null || string.Equals(input.Trim(), "/exit", StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            if (string.Equals(input.Trim(), "/help", StringComparison.OrdinalIgnoreCase))
            {
                await _output.WriteLineAsync("/help shows commands; /exit ends the conversation.");
                continue;
            }

            if (string.IsNullOrWhiteSpace(input))
            {
                continue;
            }

            await SendAndReceiveAsync(session, input, cancellationToken);
        }
    }

    private async Task SendAndReceiveAsync(
        DirectLineSession session,
        string message,
        CancellationToken cancellationToken)
    {
        var sentActivityId = await _client.SendMessageAsync(
            session,
            message,
            cancellationToken);
        var deadline = DateTimeOffset.UtcNow.Add(_options.ResponseTimeout);
        var typingDisplayed = false;
        var sentActivityObserved = false;
        var oauthChallengeHandled = false;
        var correlationIds = new HashSet<string>(StringComparer.Ordinal)
        {
            sentActivityId
        };

        while (DateTimeOffset.UtcNow < deadline)
        {
            var activities = await _client.ReceiveActivitiesAsync(session, cancellationToken);
            foreach (var activity in activities)
            {
                if (!sentActivityObserved)
                {
                    sentActivityObserved = string.Equals(
                        activity.Id,
                        sentActivityId,
                        StringComparison.Ordinal);
                    continue;
                }

                if (!ShouldProcess(activity, session))
                {
                    continue;
                }

                var isCorrelated = !string.IsNullOrWhiteSpace(activity.ReplyToId)
                    && correlationIds.Contains(activity.ReplyToId);
                if (!isCorrelated && !oauthChallengeHandled)
                {
                    continue;
                }

                if (string.Equals(activity.Type, "typing", StringComparison.OrdinalIgnoreCase))
                {
                    if (!typingDisplayed)
                    {
                        await _output.WriteLineAsync("agent> [typing]");
                        typingDisplayed = true;
                    }

                    continue;
                }

                if (!string.Equals(activity.Type, "message", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                typingDisplayed = false;
                var oauthHandled = await RenderAttachmentsAsync(
                    activity,
                    session,
                    correlationIds,
                    cancellationToken);
                if (oauthHandled)
                {
                    oauthChallengeHandled = true;
                    deadline = DateTimeOffset.UtcNow.Add(_options.ResponseTimeout);
                    continue;
                }

                if (!string.IsNullOrWhiteSpace(activity.Text))
                {
                    await _output.WriteLineAsync($"agent> {activity.Text}");
                    return;
                }
            }

            await _delay(_options.PollInterval, cancellationToken);
        }

        throw new TimeoutException(
            $"The agent did not reply within {_options.ResponseTimeout.TotalSeconds:F0} seconds.");
    }

    private async Task RunSitListAsync(
        DirectLineSession session,
        CancellationToken cancellationToken)
    {
        var prompts = await SensitivePromptList.LoadAsync(
            _options.SitListPath!,
            cancellationToken);
        await _output.WriteLineAsync(
            $"SIT mode loaded {prompts.Count} synthetic prompts. Prompt values are not echoed.");

        for (var index = 0; index < prompts.Count; index++)
        {
            await _output.WriteLineAsync($"sit> [{index + 1}/{prompts.Count}] sending");
            await SendAndReceiveAsync(session, prompts[index], cancellationToken);
            if (index + 1 < prompts.Count)
            {
                await _delay(_options.SitInterval, cancellationToken);
            }
        }
    }

    private bool ShouldProcess(DirectLineActivity activity, DirectLineSession session)
    {
        if (string.Equals(activity.From?.Id, session.UserId, StringComparison.Ordinal))
        {
            return false;
        }

        return string.IsNullOrWhiteSpace(activity.Id) || _seenActivityIds.Add(activity.Id);
    }

    private async Task<bool> RenderAttachmentsAsync(
        DirectLineActivity activity,
        DirectLineSession session,
        HashSet<string> correlationIds,
        CancellationToken cancellationToken)
    {
        var oauthHandled = false;
        foreach (var attachment in activity.Attachments)
        {
            if (DirectLineOAuthCardParser.TryParse(attachment, out var card))
            {
                var verificationActivityId = await HandleOAuthCardAsync(
                    session,
                    card!,
                    cancellationToken);
                if (!string.IsNullOrWhiteSpace(verificationActivityId))
                {
                    correlationIds.Add(verificationActivityId);
                }

                oauthHandled = true;
            }
            else if (!string.IsNullOrWhiteSpace(attachment.ContentType))
            {
                await _output.WriteLineAsync($"agent> [attachment: {attachment.ContentType}]");
            }
        }

        return oauthHandled;
    }

    private async Task<string?> HandleOAuthCardAsync(
        DirectLineSession session,
        DirectLineOAuthCard card,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(card.Text))
        {
            await _output.WriteLineAsync($"agent> {card.Text}");
        }

        await _output.WriteLineAsync($"sign-in> {card.SignInUri.AbsoluteUri}");
        if (_options.LaunchBrowser)
        {
            try
            {
                _launchBrowser(card.SignInUri);
            }
            catch (InvalidOperationException exception)
            {
                await _output.WriteLineAsync($"sign-in> Browser launch failed: {exception.Message}");
            }
            catch (Win32Exception exception)
            {
                await _output.WriteLineAsync($"sign-in> Browser launch failed: {exception.Message}");
            }
        }

        await _output.WriteAsync(
            "verification code> Enter the code shown after sign-in, or press Enter if sign-in completed automatically: ");
        await _output.FlushAsync(cancellationToken);
        var code = await _input.ReadLineAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(code))
        {
            await _output.WriteLineAsync("sign-in> Waiting for automatic completion.");
            return null;
        }

        var verificationActivityId = await _client.SendVerificationCodeAsync(
            session,
            code,
            cancellationToken);
        await _output.WriteLineAsync("sign-in> Verification code submitted.");
        return verificationActivityId;
    }

    private static void LaunchBrowser(Uri uri)
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = uri.AbsoluteUri,
            UseShellExecute = true
        });
    }
}
