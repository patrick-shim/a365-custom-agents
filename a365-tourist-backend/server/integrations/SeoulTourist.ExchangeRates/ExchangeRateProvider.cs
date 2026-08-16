using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace SeoulTourist.ExchangeRates;

public sealed partial class ExchangeRateProvider(
    KoreaEximbankExchangeRateProvider koreaEximbank,
    ForexRateApiExchangeRateProvider forexRateApi,
    FrankfurterExchangeRateProvider frankfurter,
    ILogger<ExchangeRateProvider> logger) : IExchangeRateProvider
{
    public async Task<ExchangeRateQuote> GetRateAsync(
        string sourceCurrency,
        string targetCurrency,
        DateOnly? asOfDate = null,
        CancellationToken cancellationToken = default)
    {
        var source = CurrencyCodes.Normalize(sourceCurrency, nameof(sourceCurrency));
        var target = CurrencyCodes.Normalize(targetCurrency, nameof(targetCurrency));
        if (string.Equals(source, target, StringComparison.Ordinal))
        {
            var now = DateTimeOffset.UtcNow;
            return new ExchangeRateQuote(
                source,
                target,
                1m,
                now,
                new ExchangeRateSource(
                    "Identity conversion",
                    "https://www.iso.org/iso-4217-currency-codes.html",
                    "Identity rate",
                    "The source and target currencies are identical.",
                    now));
        }

        try
        {
            if (await koreaEximbank.TryGetRateAsync(
                    source,
                    target,
                    asOfDate,
                    cancellationToken) is { } officialRate)
            {
                return officialRate;
            }
        }
        catch (Exception exception) when (IsProviderFailure(exception, cancellationToken))
        {
            LogOfficialProviderFailure(logger, exception.GetType().Name);
        }

        try
        {
            if (await forexRateApi.TryGetRateAsync(
                    source,
                    target,
                    asOfDate,
                    cancellationToken) is { } marketRate)
            {
                return marketRate;
            }
        }
        catch (Exception exception) when (IsProviderFailure(exception, cancellationToken))
        {
            LogMarketProviderFailure(logger, exception.GetType().Name);
        }

        if (await frankfurter.TryGetRateAsync(
            source,
            target,
            asOfDate,
            cancellationToken) is { } referenceRate)
        {
            return referenceRate;
        }

        throw new InvalidOperationException(
            $"No configured exchange-rate provider returned a rate for {source}/{target}.");
    }

    private static bool IsProviderFailure(
        Exception exception,
        CancellationToken cancellationToken) =>
        exception switch
        {
            HttpRequestException http when http.StatusCode is null => true,
            HttpRequestException http => http.StatusCode is HttpStatusCode.RequestTimeout
                or HttpStatusCode.TooManyRequests
                or HttpStatusCode.InternalServerError
                or HttpStatusCode.BadGateway
                or HttpStatusCode.ServiceUnavailable
                or HttpStatusCode.GatewayTimeout,
            JsonException or InvalidDataException => true,
            TaskCanceledException => !cancellationToken.IsCancellationRequested,
            _ => false
        };

    [LoggerMessage(
        EventId = 4001,
        Level = LogLevel.Warning,
        Message = "The Korea Eximbank reference-rate provider failed; trying the configured market-rate fallback. exceptionType={ExceptionType}.")]
    private static partial void LogOfficialProviderFailure(ILogger logger, string exceptionType);

    [LoggerMessage(
        EventId = 4002,
        Level = LogLevel.Warning,
        Message = "The configured market-rate provider failed; trying the ECB reference-rate fallback. exceptionType={ExceptionType}.")]
    private static partial void LogMarketProviderFailure(ILogger logger, string exceptionType);
}
