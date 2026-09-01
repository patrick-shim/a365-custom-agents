using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace JapanExpert.ExchangeRates;

/// <summary>
/// Registers the credential-free exchange-rate stack used by the currency MCP service.
/// </summary>
public static class ExchangeRateServiceCollectionExtensions
{
    public static IServiceCollection AddJapanExchangeRates(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(configuration);

        services
            .AddOptions<FrankfurterOptions>()
            .Bind(configuration.GetSection(FrankfurterOptions.SectionName))
            .ValidateDataAnnotations()
            .Validate(
                options => options.IsValid(),
                "Frankfurter:BaseAddress must be an absolute HTTPS prefix ending with a slash and "
                + "Frankfurter:Providers must name at least one publisher.")
            .ValidateOnStart();

        services
            .AddOptions<EcbSdmxOptions>()
            .Bind(configuration.GetSection(EcbSdmxOptions.SectionName))
            .ValidateDataAnnotations()
            .Validate(
                options => options.IsValid(),
                "EcbSdmx:BaseAddress must be an absolute HTTPS prefix ending with a slash.")
            .ValidateOnStart();

        services.AddHttpClient<FrankfurterExchangeRateProvider>((provider, client) =>
        {
            var options = provider.GetRequiredService<IOptions<FrankfurterOptions>>().Value;
            client.BaseAddress = new Uri(options.BaseAddress);
            client.Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds);
            client.MaxResponseContentBufferSize = options.MaximumResponseBytes;
        }).RemoveAllLoggers();

        services.AddHttpClient<EcbSdmxExchangeRateProvider>((provider, client) =>
        {
            var options = provider.GetRequiredService<IOptions<EcbSdmxOptions>>().Value;
            client.BaseAddress = new Uri(options.BaseAddress);
            client.Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds);
            client.MaxResponseContentBufferSize = options.MaximumResponseBytes;
        }).RemoveAllLoggers();

        services
            .AddOptions<ExchangeRateCacheOptions>()
            .Bind(configuration.GetSection(ExchangeRateCacheOptions.SectionName))
            .ValidateDataAnnotations()
            .Validate(
                options => options.MaximumEntrySize <= options.SizeLimit,
                "Cache:MaximumEntrySize must not exceed Cache:SizeLimit.")
            .ValidateOnStart();

        services.TryAddTimeProvider();
        services.AddSingleton<ExchangeRateResponseCache>();
        services.AddTransient<ExchangeRateProvider>();
        services.AddTransient<IExchangeRateProvider>(provider => new CachedExchangeRateProvider(
            provider.GetRequiredService<ExchangeRateProvider>(),
            provider.GetRequiredService<ExchangeRateResponseCache>(),
            provider.GetRequiredService<IOptions<ExchangeRateCacheOptions>>(),
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
