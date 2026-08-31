namespace SeoulTourist.Direct;

internal static class Program
{
    public static async Task<int> Main(string[] args)
    {
        if (args.Any(argument => argument is "--help" or "-h"))
        {
            Console.WriteLine(DirectClientOptions.GetHelpText());
            return 0;
        }

        try
        {
            var options = DirectClientOptions.Parse(args);
            using var cancellation = new CancellationTokenSource();
            Console.CancelKeyPress += (_, eventArgs) =>
            {
                eventArgs.Cancel = true;
                cancellation.Cancel();
            };

            using var httpClient = new HttpClient();
            var client = new DirectLineClient(httpClient, options.Endpoint);
            var conversation = new ConsoleConversation(client, options);
            await conversation.RunAsync(cancellation.Token);
            return 0;
        }
        catch (DirectClientOptionsException exception)
        {
            Console.Error.WriteLine($"Configuration error: {exception.Message}");
            Console.Error.WriteLine("Use --help for usage.");
            return 2;
        }
        catch (SensitivePromptListException exception)
        {
            Console.Error.WriteLine($"SIT list error: {exception.Message}");
            return 2;
        }
        catch (OperationCanceledException)
        {
            Console.Error.WriteLine("Cancelled.");
            return 130;
        }
        catch (Exception exception) when (
            exception is DirectLineProtocolException or HttpRequestException or TimeoutException)
        {
            var code = exception is DirectLineProtocolException protocol
                ? protocol.Code
                : "DL-DEP-004";
            Console.Error.WriteLine($"Direct Line error: {exception.Message} Error code: {code}.");
            return 1;
        }
    }
}
