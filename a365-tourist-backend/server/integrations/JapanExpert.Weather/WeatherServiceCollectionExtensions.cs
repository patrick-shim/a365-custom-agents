using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace JapanExpert.Weather;

/// <summary>
/// Registers the Japan weather stack: the Japan Meteorological Agency as the authoritative
/// forecast and alert source, and MET Norway as a clearly labelled third-party
/// current-conditions source. No source requires a credential.
/// </summary>
public static class WeatherServiceCollectionExtensions
{
    public static IServiceCollection AddJapanWeather(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(configuration);

        services.TryAddTimeProvider();

        services
            .AddOptions<JmaOptions>()
            .Bind(configuration.GetSection(JmaOptions.SectionName))
            .ValidateDataAnnotations()
            .Validate(
                options => options.IsValid(),
                "Jma:ForecastBaseAddress must be an absolute HTTPS prefix ending with a slash, "
                + "Jma:AlertFeedAddress must be an absolute HTTPS URI, and at least one alert title "
                + "keyword is required.")
            .ValidateOnStart();

        services
            .AddOptions<MetNorwayOptions>()
            .Bind(configuration.GetSection(MetNorwayOptions.SectionName))
            .ValidateDataAnnotations()
            .Validate(
                options => options.IsValid(),
                "MetNorway:BaseAddress must be an absolute HTTPS prefix ending with a slash and "
                + "MetNorway:UserAgent must identify this application and carry a '+URL' project "
                + "link or a mailto contact.")
            .ValidateOnStart();

        services.AddHttpClient<JmaForecastProvider>((provider, client) =>
        {
            var options = provider.GetRequiredService<IOptions<JmaOptions>>().Value;
            client.Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds);
            client.MaxResponseContentBufferSize = options.MaximumResponseBytes;
        }).RemoveAllLoggers();

        services.AddHttpClient<JmaAlertFeedProvider>((provider, client) =>
        {
            var options = provider.GetRequiredService<IOptions<JmaOptions>>().Value;
            client.Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds);
            client.MaxResponseContentBufferSize = options.MaximumResponseBytes;
        }).RemoveAllLoggers();

        services.AddHttpClient<MetNorwayCurrentWeatherProvider>((provider, client) =>
        {
            var options = provider.GetRequiredService<IOptions<MetNorwayOptions>>().Value;
            client.BaseAddress = new Uri(options.BaseAddress);
            client.Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds);
            client.MaxResponseContentBufferSize = options.MaximumResponseBytes;
        }).RemoveAllLoggers();

        services
            .AddOptions<WeatherCacheOptions>()
            .Bind(configuration.GetSection(WeatherCacheOptions.SectionName))
            .ValidateDataAnnotations()
            .Validate(
                options => options.MaximumEntrySize <= options.SizeLimit,
                "Cache:MaximumEntrySize must not exceed Cache:SizeLimit.")
            .ValidateOnStart();

        services.AddSingleton<WeatherResponseCache>();
        services.AddTransient<IWeatherForecastProvider>(provider =>
            new CachedWeatherForecastProvider(
                provider.GetRequiredService<JmaForecastProvider>(),
                provider.GetRequiredService<WeatherResponseCache>(),
                provider.GetRequiredService<IOptions<WeatherCacheOptions>>(),
                provider.GetRequiredService<TimeProvider>()));
        services.AddTransient<IWeatherAlertProvider>(provider =>
            new CachedWeatherAlertProvider(
                provider.GetRequiredService<JmaAlertFeedProvider>(),
                provider.GetRequiredService<WeatherResponseCache>(),
                provider.GetRequiredService<IOptions<WeatherCacheOptions>>(),
                provider.GetRequiredService<TimeProvider>()));
        services.AddTransient<ICurrentWeatherProvider>(provider =>
            new CachedCurrentWeatherProvider(
                provider.GetRequiredService<MetNorwayCurrentWeatherProvider>(),
                provider.GetRequiredService<WeatherResponseCache>(),
                provider.GetRequiredService<IOptions<WeatherCacheOptions>>(),
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
