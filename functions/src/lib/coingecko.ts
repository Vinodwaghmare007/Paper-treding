export class CoinGeckoApiError extends Error {
  constructor(
    message: string,
    public readonly statusCode?: number,
  ) {
    super(message);
    this.name = "CoinGeckoApiError";
  }
}

const BASE_URL = "https://api.coingecko.com/api/v3";

/** GET /coins/markets for every id in `ids` in ONE request — mirrors
 * lib/data/sources/coingecko_source.dart's Flutter-side equivalent.
 * Returns a Map keyed by CoinGecko id -> current USD price. */
export async function fetchMarketPrices(ids: string[]): Promise<Map<string, number>> {
  if (ids.length === 0) return new Map();

  const query = new URLSearchParams({
    vs_currency: "usd",
    ids: ids.join(","),
  });
  const response = await fetch(`${BASE_URL}/coins/markets?${query.toString()}`);
  if (!response.ok) {
    throw new CoinGeckoApiError(
      `CoinGecko /coins/markets request failed: HTTP ${response.status}`,
      response.status,
    );
  }

  const raw = (await response.json()) as Array<{ id: string; current_price: number }>;
  return new Map(raw.map((entry) => [entry.id, entry.current_price]));
}
