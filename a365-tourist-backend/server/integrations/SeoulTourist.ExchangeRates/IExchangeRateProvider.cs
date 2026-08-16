namespace SeoulTourist.ExchangeRates;

public interface IExchangeRateProvider
{
    Task<ExchangeRateQuote> GetRateAsync(
        string sourceCurrency,
        string targetCurrency,
        DateOnly? asOfDate = null,
        CancellationToken cancellationToken = default);
}
