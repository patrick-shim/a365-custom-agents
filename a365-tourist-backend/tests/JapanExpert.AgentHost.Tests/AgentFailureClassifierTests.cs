using System.ClientModel;
using System.ClientModel.Primitives;
using System.Net;
using System.Text.Json;
using Azure;
using JapanExpert.AgentHost;

namespace JapanExpert.AgentHost.Tests;

[TestClass]
public sealed class AgentFailureClassifierTests
{
    public static IEnumerable<object[]> KnownFailures =>
    [
        [new TimeoutException("canary"), "Timeout", "JEX-DEP-001"],
        [new OperationCanceledException("canary"), "Timeout", "JEX-DEP-001"],
        [new HttpRequestException("canary", null, HttpStatusCode.Unauthorized), "Authentication", "JEX-AUTH-001"],
        [new HttpRequestException("canary", null, HttpStatusCode.Forbidden), "Authorization", "JEX-AUTHZ-001"],
        [new HttpRequestException("canary", null, HttpStatusCode.TooManyRequests), "Throttled", "JEX-DEP-002"],
        [new HttpRequestException("canary", null, HttpStatusCode.ServiceUnavailable), "Unavailable", "JEX-DEP-004"],
        [new JsonException("canary"), "InvalidResponse", "JEX-DEP-003"],
        // The Foundry Responses client surfaces transport failures as ClientResultException.
        [ModelFailure(HttpStatusCode.TooManyRequests), "Throttled", "JEX-DEP-002"],
        [ModelFailure(HttpStatusCode.Unauthorized), "Authentication", "JEX-AUTH-001"],
        [ModelFailure(HttpStatusCode.ServiceUnavailable), "Unavailable", "JEX-DEP-004"]
    ];

    [TestMethod]
    [DynamicData(nameof(KnownFailures))]
    public void ClassifiesKnownFailures(
        Exception exception,
        string expectedKind,
        string expectedCode)
    {
        var failure = AgentFailureClassifier.Classify(exception);

        Assert.AreEqual(expectedKind, failure.Kind.ToString());
        Assert.AreEqual(expectedCode, failure.Code);
        Assert.DoesNotContain("canary", failure.UserMessage, StringComparison.Ordinal);
    }

    [TestMethod]
    public void UsesBoundaryFallbackForUnknownFailure()
    {
        var failure = AgentFailureClassifier.Classify(
            new InvalidOperationException("canary"),
            AgentFailureKind.Unavailable);

        Assert.AreEqual(AgentFailureKind.Unavailable, failure.Kind);
        Assert.AreEqual("JEX-DEP-004", failure.Code);
        Assert.DoesNotContain("canary", failure.UserMessage, StringComparison.Ordinal);
    }

    [TestMethod]
    public void ReportsDependencyStatusForDiagnosableFailures()
    {
        Assert.AreEqual(429, AgentFailureClassifier.GetDependencyStatus(ModelFailure(HttpStatusCode.TooManyRequests)));
        Assert.AreEqual(503, AgentFailureClassifier.GetDependencyStatus(new RequestFailedException(503, "canary")));
        Assert.AreEqual(
            401,
            AgentFailureClassifier.GetDependencyStatus(
                new HttpRequestException("canary", null, HttpStatusCode.Unauthorized)));
        Assert.AreEqual(0, AgentFailureClassifier.GetDependencyStatus(new InvalidOperationException("canary")));
    }

    private static ClientResultException ModelFailure(HttpStatusCode status) =>
        new(new StubPipelineResponse((int)status));

    private sealed class StubPipelineResponse(int status) : PipelineResponse
    {
        private readonly BinaryData _content = BinaryData.FromString(string.Empty);

        public override int Status { get; } = status;

        public override string ReasonPhrase => "canary";

        public override Stream? ContentStream { get; set; }

        public override BinaryData Content => _content;

        protected override PipelineResponseHeaders HeadersCore => new StubHeaders();

        public override BinaryData BufferContent(CancellationToken cancellationToken = default) => _content;

        public override ValueTask<BinaryData> BufferContentAsync(CancellationToken cancellationToken = default) =>
            new(_content);

        public override void Dispose()
        {
        }
    }

    private sealed class StubHeaders : PipelineResponseHeaders
    {
        public override IEnumerator<KeyValuePair<string, string>> GetEnumerator() =>
            Enumerable.Empty<KeyValuePair<string, string>>().GetEnumerator();

        public override bool TryGetValue(string name, out string? value)
        {
            value = null;
            return false;
        }

        public override bool TryGetValues(string name, out IEnumerable<string>? values)
        {
            values = null;
            return false;
        }
    }
}
