using JapanExpert.Mcp.Hosting;
using JapanExpert.Mcp.Weather;
using JapanExpert.Weather;

var builder = WebApplication.CreateBuilder(args);
var isLocalEnvironment = builder.Environment.IsDevelopment();

builder.Services.AddMcpWorkloadAuthorization(builder.Configuration, isLocalEnvironment);
builder.Services.AddJapanWeather(builder.Configuration);
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
