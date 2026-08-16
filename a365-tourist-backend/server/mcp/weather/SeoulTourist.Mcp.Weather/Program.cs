using SeoulTourist.Mcp.Weather;
using SeoulTourist.Mcp.Hosting;
using SeoulTourist.Weather;

var builder = WebApplication.CreateBuilder(args);
var isLocalEnvironment = builder.Environment.IsDevelopment();

builder.Services.AddMcpWorkloadAuthorization(builder.Configuration, isLocalEnvironment);
builder.Services
    .AddOptions<OpenMeteoOptions>()
    .Bind(builder.Configuration.GetSection(OpenMeteoOptions.SectionName))
    .ValidateDataAnnotations()
    .Validate(
        options => !options.RequireCommercialLicense
            || (!string.IsNullOrWhiteSpace(options.ApiKey)
                && Uri.TryCreate(options.BaseAddress, UriKind.Absolute, out var baseAddress)
                && string.Equals(
                    baseAddress.Host,
                    "customer-api.open-meteo.com",
                    StringComparison.OrdinalIgnoreCase)),
        "A commercial Open-Meteo deployment requires the customer endpoint and API key.")
    .Validate(
        options => Uri.TryCreate(options.BaseAddress, UriKind.Absolute, out var baseAddress)
            && (baseAddress.Scheme == Uri.UriSchemeHttps
                || (isLocalEnvironment && baseAddress.IsLoopback)),
        "OpenMeteo:BaseAddress must use HTTPS outside loopback development.")
    .ValidateOnStart();
builder.Services
    .AddOptions<OpenWeatherOptions>()
    .Bind(builder.Configuration.GetSection(OpenWeatherOptions.SectionName))
    .ValidateDataAnnotations()
    .Validate(
        options => !options.Enabled || !string.IsNullOrWhiteSpace(options.ApiKey),
        "OpenWeather:ApiKey is required when the One Call 4.0 fallback is enabled.")
    .Validate(
        options => Uri.TryCreate(options.BaseAddress, UriKind.Absolute, out var baseAddress)
            && (baseAddress.Scheme == Uri.UriSchemeHttps
                || (isLocalEnvironment && baseAddress.IsLoopback)),
        "OpenWeather:BaseAddress must use HTTPS outside loopback development.")
    .ValidateOnStart();
builder.Services.AddHttpClient<OpenMeteoWeatherProvider>((services, client) =>
{
    var options = services
        .GetRequiredService<Microsoft.Extensions.Options.IOptions<OpenMeteoOptions>>()
        .Value;
    client.BaseAddress = new Uri(options.BaseAddress);
    client.Timeout = TimeSpan.FromSeconds(20);
    client.MaxResponseContentBufferSize = 1024 * 1024;
}).RemoveAllLoggers();
builder.Services.AddHttpClient<OpenWeatherOneCallProvider>((services, client) =>
{
    var options = services
        .GetRequiredService<Microsoft.Extensions.Options.IOptions<OpenWeatherOptions>>()
        .Value;
    client.BaseAddress = new Uri(options.BaseAddress);
    client.Timeout = TimeSpan.FromSeconds(20);
    client.MaxResponseContentBufferSize = 1024 * 1024;
}).RemoveAllLoggers();
builder.Services.AddTransient<IWeatherProvider, FallbackWeatherProvider>();
builder.Services.AddSingleton<UnavailableWeatherAlertProvider>();
builder.Services.AddTransient<IWeatherAlertProvider>(services =>
    services.GetRequiredService<Microsoft.Extensions.Options.IOptions<OpenWeatherOptions>>()
        .Value.Enabled
        ? services.GetRequiredService<OpenWeatherOneCallProvider>()
        : services.GetRequiredService<UnavailableWeatherAlertProvider>());
builder.Services
    .AddMcpServer()
    .WithHttpTransport(options => options.Stateless = true)
    .WithTools<WeatherTools>();

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

app.MapMcp("/mcp").RequireMcpWorkloadAuthorization(isLocalEnvironment);
app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "weather" }));
app.Run();

public partial class Program;
