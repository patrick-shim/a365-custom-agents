namespace JapanExpert.ExchangeRates;

/// <summary>Narrow exchange-rate contract consumed by the currency MCP service.</summary>
public interface IExchangeRateProvider
{
    Task<ExchangeRateQuote> GetRateAsync(
        string sourceCurrency,
        string targetCurrency,
        DateOnly? asOfDate = null,
        CancellationToken cancellationToken = default);
}
