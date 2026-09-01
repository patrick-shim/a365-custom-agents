using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace JapanExpert.Tourism;

/// <summary>
/// Shared registration for the Japan OpenStreetMap tourism provider so the attractions and
/// accommodation MCP services stay independently deployable without duplicating transport rules.
/// </summary>
public static class TourismServiceCollectionExtensions
{
    public static IServiceCollection AddOverpassTourism(
        this IServiceCollection services,
        IConfiguration configuration,
        bool isLocalEnvironment)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(configuration);

        services
            .AddOptions<OverpassOptions>()
            .Bind(configuration.GetSection(OverpassOptions.SectionName))
            .ValidateDataAnnotations()
            .Validate(
                options => options.IsValid(),
                "Overpass:Endpoint must be an absolute HTTPS URI and Overpass:UserAgent must be an "
                + "informative agent string of at least 16 characters carrying a '+URL' project "
                + "link or a mailto contact.")
            .Validate(
                options => isLocalEnvironment
                    || (Uri.TryCreate(options.Endpoint, UriKind.Absolute, out var endpoint)
                        && endpoint.Scheme == Uri.UriSchemeHttps),
                "Overpass:Endpoint must use HTTPS outside local development.")
            .ValidateOnStart();

        services.AddHttpClient<OverpassClient>((provider, client) =>
        {
            var options = provider.GetRequiredService<IOptions<OverpassOptions>>().Value;
            client.Timeout = TimeSpan.FromSeconds(options.QueryTimeoutSeconds + 10);
            client.MaxResponseContentBufferSize = options.MaximumResponseBytes;
        }).RemoveAllLoggers();

        services
            .AddOptions<TourismCacheOptions>()
            .Bind(configuration.GetSection(TourismCacheOptions.SectionName))
            .ValidateDataAnnotations()
            .Validate(
                options => options.MaximumEntrySize <= options.SizeLimit,
                "Cache:MaximumEntrySize must not exceed Cache:SizeLimit.")
            .ValidateOnStart();

        services.TryAddTimeProvider();
        services.AddSingleton<TourismResponseCache>();
        services.AddTransient<OverpassTourismProvider>();
        services.AddTransient<ITourismProvider>(provider => new CachedTourismProvider(
            provider.GetRequiredService<OverpassTourismProvider>(),
            provider.GetRequiredService<TourismResponseCache>(),
            provider.GetRequiredService<IOptions<TourismCacheOptions>>(),
            provider.GetRequiredService<TimeProvider>()));
        return services;
    }

    private static void TryAddTimeProvider(this IServiceCollection services)
    {
        if (services.All(descriptor => descriptor.ServiceType != typeof(TimeProvider)))
        {
            services.AddSingleton(TimeProvider.System);
        }
    }
}
