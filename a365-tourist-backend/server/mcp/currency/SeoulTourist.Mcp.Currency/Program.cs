using SeoulTourist.ExchangeRates;
using SeoulTourist.Mcp.Currency;
using SeoulTourist.Mcp.Hosting;

var builder = WebApplication.CreateBuilder(args);
var isLocalEnvironment = builder.Environment.IsDevelopment();
if (!isLocalEnvironment
    && !builder.Configuration.GetValue("KoreaEximbank:Enabled", false)
    && !builder.Configuration.GetValue("ForexRateApi:Enabled", false)
    && !builder.Configuration.GetValue("Frankfurter:Enabled", false))
{
    throw new InvalidOperationException(
        "At least one exchange-rate provider must be enabled outside local development.");
}

builder.Services.AddMcpWorkloadAuthorization(builder.Configuration, isLocalEnvironment);
builder.Services
    .AddOptions<KoreaEximbankOptions>()
    .Bind(builder.Configuration.GetSection(KoreaEximbankOptions.SectionName))
    .ValidateDataAnnotations()
    .Validate(
        options => !options.Enabled || !string.IsNullOrWhiteSpace(options.AuthKey),
        "KoreaEximbank:AuthKey is required when the provider is enabled.")
    .Validate(
        options => Uri.TryCreate(options.BaseAddress, UriKind.Absolute, out var baseAddress)
            && (baseAddress.Scheme == Uri.UriSchemeHttps
                || (isLocalEnvironment && baseAddress.IsLoopback)),
        "KoreaEximbank:BaseAddress must use HTTPS outside loopback development.")
    .ValidateOnStart();
builder.Services
    .AddOptions<ForexRateApiOptions>()
    .Bind(builder.Configuration.GetSection(ForexRateApiOptions.SectionName))
    .ValidateDataAnnotations()
    .Validate(
        options => !options.Enabled || !string.IsNullOrWhiteSpace(options.ApiKey),
        "ForexRateApi:ApiKey is required when the provider is enabled.")
    .Validate(
        options => Uri.TryCreate(options.BaseAddress, UriKind.Absolute, out var baseAddress)
            && (baseAddress.Scheme == Uri.UriSchemeHttps
                || (isLocalEnvironment && baseAddress.IsLoopback)),
        "ForexRateApi:BaseAddress must use HTTPS outside loopback development.")
    .ValidateOnStart();
builder.Services
    .AddOptions<FrankfurterOptions>()
    .Bind(builder.Configuration.GetSection(FrankfurterOptions.SectionName))
    .ValidateDataAnnotations()
    .Validate(
        options => Uri.TryCreate(options.BaseAddress, UriKind.Absolute, out var baseAddress)
            && (baseAddress.Scheme == Uri.UriSchemeHttps
                || (isLocalEnvironment && baseAddress.IsLoopback)),
        "Frankfurter:BaseAddress must use HTTPS outside loopback development.")
    .ValidateOnStart();
builder.Services.AddHttpClient<KoreaEximbankExchangeRateProvider>((services, client) =>
{
    var options = services
        .GetRequiredService<Microsoft.Extensions.Options.IOptions<KoreaEximbankOptions>>()
        .Value;
    client.BaseAddress = new Uri(options.BaseAddress);
    client.Timeout = TimeSpan.FromSeconds(20);
    client.MaxResponseContentBufferSize = 1024 * 1024;
}).RemoveAllLoggers();
builder.Services.AddHttpClient<ForexRateApiExchangeRateProvider>((services, client) =>
{
    var options = services
        .GetRequiredService<Microsoft.Extensions.Options.IOptions<ForexRateApiOptions>>()
        .Value;
    client.BaseAddress = new Uri(options.BaseAddress);
    client.Timeout = TimeSpan.FromSeconds(20);
    client.MaxResponseContentBufferSize = 1024 * 1024;
}).RemoveAllLoggers();
builder.Services.AddHttpClient<FrankfurterExchangeRateProvider>((services, client) =>
{
    var options = services
        .GetRequiredService<Microsoft.Extensions.Options.IOptions<FrankfurterOptions>>()
        .Value;
    client.BaseAddress = new Uri(options.BaseAddress);
    client.Timeout = TimeSpan.FromSeconds(20);
    client.MaxResponseContentBufferSize = 1024 * 1024;
}).RemoveAllLoggers();
builder.Services.AddTransient<IExchangeRateProvider, ExchangeRateProvider>();
builder.Services
    .AddMcpServer()
    .WithHttpTransport(options => options.Stateless = true)
    .WithTools<CurrencyTools>()
    .WithTools<ExchangeRateTools>();

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

app.MapMcp("/mcp").RequireMcpWorkloadAuthorization(isLocalEnvironment);
app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "currency" }));
app.Run();

public partial class Program;
