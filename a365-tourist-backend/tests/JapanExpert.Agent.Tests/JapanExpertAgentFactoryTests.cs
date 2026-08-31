using System.Runtime.CompilerServices;
using JapanExpert.Agent;
using Microsoft.Extensions.AI;

namespace JapanExpert.Agent.Tests;

[TestClass]
public sealed class JapanExpertAgentFactoryTests
{
    [TestMethod]
    public void CreateUsesJapanExpertProductName()
    {
        using var chatClient = new RecordingChatClient();

        var agent = JapanExpertAgentFactory.Create(chatClient, []);

        Assert.AreEqual("Japan Expert", agent.Name);
    }

    [TestMethod]
    public async Task RunSendsJapanExpertInstructionsAndToolsToTheChatClient()
    {
        using var chatClient = new RecordingChatClient();
        var tool = AIFunctionFactory.Create(() => "ok", "search_attractions");
        var agent = JapanExpertAgentFactory.Create(chatClient, [tool]);

        await agent.RunAsync("Plan two days in Kanazawa.", cancellationToken: TestContext.CancellationTokenSource.Token);

        var promptedInstructions = string.Join(
            "\n",
            [
                chatClient.LastOptions?.Instructions ?? string.Empty,
                .. chatClient.LastMessages?.Select(message => message.Text) ?? []
            ]);
        StringAssert.Contains(promptedInstructions, "You are Japan Expert");
        StringAssert.Contains(promptedInstructions, "Japan Standard Time (JST, UTC+9)");
        Assert.IsNotNull(chatClient.LastOptions?.Tools);
        Assert.HasCount(1, chatClient.LastOptions.Tools);
        Assert.AreSame(tool, chatClient.LastOptions.Tools[0]);
    }

    [TestMethod]
    public void CreateAppliesAgentIdOnlyWhenSupplied()
    {
        using var chatClient = new RecordingChatClient();

        var withoutId = JapanExpertAgentFactory.Create(chatClient, []);
        var withId = JapanExpertAgentFactory.Create(chatClient, [], "agent-42");
        var withBlankId = JapanExpertAgentFactory.Create(chatClient, [], "   ");

        Assert.AreEqual("agent-42", withId.Id);
        Assert.AreNotEqual("agent-42", withoutId.Id);
        Assert.AreNotEqual("   ", withBlankId.Id);
    }

    [TestMethod]
    public void CreateRejectsMissingArguments()
    {
        using var chatClient = new RecordingChatClient();

        Assert.ThrowsExactly<ArgumentNullException>(() => JapanExpertAgentFactory.Create(null!, []));
        Assert.ThrowsExactly<ArgumentNullException>(() => JapanExpertAgentFactory.Create(chatClient, null!));
    }

    public TestContext TestContext { get; set; } = null!;

    private sealed class RecordingChatClient : IChatClient
    {
        public IReadOnlyList<ChatMessage>? LastMessages { get; private set; }

        public ChatOptions? LastOptions { get; private set; }

        public void Dispose()
        {
        }

        public Task<ChatResponse> GetResponseAsync(
            IEnumerable<ChatMessage> messages,
            ChatOptions? options = null,
            CancellationToken cancellationToken = default)
        {
            LastMessages = [.. messages];
            LastOptions = options;
            return Task.FromResult(new ChatResponse(new ChatMessage(ChatRole.Assistant, "ok")));
        }

        public async IAsyncEnumerable<ChatResponseUpdate> GetStreamingResponseAsync(
            IEnumerable<ChatMessage> messages,
            ChatOptions? options = null,
            [EnumeratorCancellation] CancellationToken cancellationToken = default)
        {
            LastMessages = [.. messages];
            LastOptions = options;
            await Task.Yield();
            yield return new ChatResponseUpdate(ChatRole.Assistant, "ok");
        }

        public object? GetService(Type serviceType, object? serviceKey = null) =>
            serviceType.IsInstanceOfType(this) ? this : null;
    }
}
