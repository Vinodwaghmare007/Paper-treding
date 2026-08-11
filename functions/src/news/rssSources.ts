import { getRemoteConfig } from "firebase-admin/remote-config";

export interface RssSourceConfig {
  name: string;
  url: string;
  category: string;
  /**
   * true if every item in this feed is already about crypto (skip the
   * keyword filter in newsParsing.ts entirely for it) — all 4 bundled
   * defaults below are crypto-only publications, but a source added later
   * via Remote Config (e.g. a general finance feed that only sometimes
   * covers crypto) would set this false.
   */
  cryptoExclusive: boolean;
}

/**
 * PRE-LAUNCH TODO: these 4 URLs were supplied as the target sources and
 * have NOT been verified live — this sandbox has no outbound network
 * access (same constraint documented on supported_coin.dart's coin list).
 * Confirm each one still resolves and returns valid RSS/Atom XML before
 * relying on it; feed URLs change without notice. aggregateNews.ts's
 * per-source try/catch means a dead URL here degrades gracefully (that
 * source just contributes zero items) rather than breaking the whole
 * pipeline, but a permanently-dead source is still a silently-empty one
 * until someone checks.
 */
export const DEFAULT_RSS_SOURCES: RssSourceConfig[] = [
  {
    name: "CoinDesk",
    url: "https://www.coindesk.com/arc/outboundfeeds/rss/",
    category: "general",
    cryptoExclusive: true,
  },
  {
    name: "CoinTelegraph",
    url: "https://cointelegraph.com/rss",
    category: "general",
    cryptoExclusive: true,
  },
  {
    name: "Decrypt",
    url: "https://decrypt.co/feed",
    category: "general",
    cryptoExclusive: true,
  },
  {
    name: "The Block",
    url: "https://www.theblock.co/rss.xml",
    category: "general",
    cryptoExclusive: true,
  },
];

/**
 * Remote Config parameter name — same key both the backend (via the
 * Admin SDK's remoteConfig().getTemplate(), read here) and the Flutter
 * app (via the client SDK, see remote_config_rss_source.dart) read, so
 * publishing one JSON array in the Firebase console adds/removes/fixes a
 * source for both sides at once, with no redeploy of either. Shape:
 * `[{"name":"CoinDesk","url":"https://...","category":"general",
 * "cryptoExclusive":true}, ...]`.
 */
export const rssSourcesRemoteConfigKey = "rss_sources_json";

/** Skips a malformed individual entry rather than discarding the whole
 * published list over one typo — returns an empty list only if nothing in
 * [raw] parsed at all, which the caller treats as "no live list yet." */
export function parseRssSourceConfigs(raw: string): RssSourceConfig[] {
  let decoded: unknown;
  try {
    decoded = JSON.parse(raw);
  } catch {
    return [];
  }
  if (!Array.isArray(decoded)) return [];

  const configs: RssSourceConfig[] = [];
  for (const entry of decoded) {
    if (typeof entry !== "object" || entry === null) continue;
    const { name, url, category, cryptoExclusive } = entry as Record<string, unknown>;
    if (typeof name !== "string" || typeof url !== "string" || typeof category !== "string") {
      continue;
    }
    configs.push({
      name,
      url,
      category,
      cryptoExclusive: cryptoExclusive === true,
    });
  }
  return configs;
}

/**
 * The live Remote Config source list if one has been published and parses
 * to at least one valid entry; otherwise DEFAULT_RSS_SOURCES. Never
 * throws — a Remote Config outage must degrade to the bundled list, not
 * skip a scheduled run entirely.
 */
export async function fetchRssSourceConfigs(): Promise<RssSourceConfig[]> {
  try {
    const template = await getRemoteConfig().getTemplate();
    const param = template.parameters[rssSourcesRemoteConfigKey];
    const defaultValue = param?.defaultValue;
    const raw =
      defaultValue && "value" in defaultValue ? (defaultValue.value as string) : undefined;
    if (!raw) return DEFAULT_RSS_SOURCES;

    const parsed = parseRssSourceConfigs(raw);
    return parsed.length > 0 ? parsed : DEFAULT_RSS_SOURCES;
  } catch (e) {
    console.error("[fetchRssSourceConfigs] falling back to the bundled RSS source list:", e);
    return DEFAULT_RSS_SOURCES;
  }
}
