using Azure.Core;
using Azure.Identity;
using SeoulTourist.AzureMaps;
using SeoulTourist.Mcp.Accommodation;
using SeoulTourist.Mcp.Hosting;

var builder = WebApplication.CreateBuilder(args);
var isLocalEnvironment = builder.Environment.IsDevelopment();

builder.Services.AddMcpWorkloadAuthorization(builder.Configuration, isLocalEnvironment);
builder.Services
    .AddOptions<AzureMapsOptions>()
    .Bind(builder.Configuration.GetSection(AzureMapsOptions.SectionName))
    .Validate(
        options => isLocalEnvironment || !string.IsNullOrWhiteSpace(options.ClientId),
        "AzureMaps:ClientId is required outside local development.")
    .ValidateOnStart();
builder.Services.AddSingleton<TokenCredential>(_ => new DefaultAzureCredential());
builder.Services.AddHttpClient<AzureMapsClient>(client =>
{
    client.BaseAddress = new Uri("https://atlas.microsoft.com/");
    client.Timeout = TimeSpan.FromSeconds(20);
    client.MaxResponseContentBufferSize = 1024 * 1024;
}).RemoveAllLoggers();
builder.Services
    .AddMcpServer()
    .WithHttpTransport(options => options.Stateless = true)
    .WithTools<AccommodationTools>();

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

app.MapMcp("/mcp").RequireMcpWorkloadAuthorization(isLocalEnvironment);
app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "accommodation" }));
app.Run();

public partial class Program;
