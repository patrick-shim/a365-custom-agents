using JapanExpert.Mcp.Accommodation;
using JapanExpert.Mcp.Hosting;
using JapanExpert.Tourism;

var builder = WebApplication.CreateBuilder(args);
var isLocalEnvironment = builder.Environment.IsDevelopment();

builder.Services.AddMcpWorkloadAuthorization(builder.Configuration, isLocalEnvironment);
builder.Services.AddOverpassTourism(builder.Configuration, isLocalEnvironment);
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
