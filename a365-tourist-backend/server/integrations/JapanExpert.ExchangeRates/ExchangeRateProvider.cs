using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace JapanExpert.ExchangeRates;

/// <summary>
/// Credential-free exchange-rate aggregator. Frankfurter v2 pinned to the European Central Bank
/// is the primary source; a direct ECB SDMX cross-rate read is the fallback. Both publish the
/// same underlying reference rates, so the quote provenance stays consistent either way.
/// </summary>
public sealed partial class ExchangeRateProvider(
    FrankfurterExchangeRateProvider frankfurter,
    EcbSdmxExchangeRateProvider europeanCentralBank,
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
                DateOnly.FromDateTime(now.UtcDateTime),
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
            if (await frankfurter.TryGetRateAsync(source, target, asOfDate, cancellationToken)
                is { } referenceRate)
            {
                return referenceRate;
            }
        }
        catch (Exception exception) when (IsTransientProviderFailure(exception, cancellationToken))
        {
            LogPrimaryProviderFailure(logger, exception.GetType().Name);
        }

        if (await europeanCentralBank.TryGetRateAsync(source, target, asOfDate, cancellationToken)
            is { } crossRate)
        {
            return crossRate;
        }

        throw new InvalidOperationException(
            $"No configured exchange-rate provider returned a rate for {source}/{target}.");
    }

    private static bool IsTransientProviderFailure(
        Exception exception,
        CancellationToken cancellationToken) =>
        exception switch
        {
            HttpRequestException http when http.StatusCode is null => true,
            HttpRequestException http => http.StatusCode is HttpStatusCode.RequestTimeout
                or HttpStatusCode.TooManyRequests
                or HttpStatusCode.NotFound
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
        Message = "The Frankfurter reference-rate provider failed; trying the direct European Central "
            + "Bank fallback. exceptionType={ExceptionType}.")]
    private static partial void LogPrimaryProviderFailure(ILogger logger, string exceptionType);
}
