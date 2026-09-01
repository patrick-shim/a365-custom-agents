using JapanExpert.ExchangeRates;
using JapanExpert.Mcp.Currency;
using JapanExpert.Mcp.Hosting;

var builder = WebApplication.CreateBuilder(args);
var isLocalEnvironment = builder.Environment.IsDevelopment();
if (!isLocalEnvironment
    && !builder.Configuration.GetValue("Frankfurter:Enabled", true)
    && !builder.Configuration.GetValue("EcbSdmx:Enabled", true))
{
    throw new InvalidOperationException(
        "At least one exchange-rate provider must be enabled outside local development.");
}

builder.Services.AddMcpWorkloadAuthorization(builder.Configuration, isLocalEnvironment);
builder.Services.AddJapanExchangeRates(builder.Configuration);
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
