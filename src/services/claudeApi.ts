import axios, { AxiosInstance } from 'axios';
import { QuotaLimits, RateLimit, SubscriptionMetadata } from '../types';

/**
 * Service for interacting with Claude API to fetch quota information.
 * 
 * This service handles communication with the Anthropic Claude API to retrieve
 * rate limit information from response headers. It parses both 5-hour and 7-day
 * rate limit data and provides subscription metadata.
 * 
 * @example
 * ```typescript
 * const apiService = new ClaudeApiService('your-api-key');
 * const quotaLimits = await apiService.fetchQuotaLimits();
 * console.log(quotaLimits.fiveHour.remaining);
 * ```
 */
export class ClaudeApiService {
  private client: AxiosInstance;
  private apiKey: string;

  constructor(apiKey: string, baseURL: string = 'https://api.anthropic.com') {
    this.apiKey = apiKey;
    this.client = axios.create({
      baseURL,
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
    });
  }

  /**
   * Parse rate limit headers from API response
   */
  private parseRateLimitHeaders(headers: Record<string, string>): QuotaLimits {
    const fiveHour = this.parseRateLimit(headers, 'requests-5h');
    const sevenDay = this.parseRateLimit(headers, 'requests-7d');

    return { fiveHour, sevenDay };
  }

  /**
   * Parse individual rate limit from headers
   */
  private parseRateLimit(headers: Record<string, string>, prefix: string): RateLimit {
    const limit = parseInt(headers[`anthropic-ratelimit-${prefix}-limit`] || '0', 10);
    const remaining = parseInt(headers[`anthropic-ratelimit-${prefix}-remaining`] || '0', 10);
    const resetStr = headers[`anthropic-ratelimit-${prefix}-reset`];
    const reset = resetStr ? new Date(resetStr) : new Date();
    const used = limit - remaining;
    const percentage = limit > 0 ? (used / limit) * 100 : 0;

    return { limit, remaining, reset, used, percentage };
  }

  /**
   * Fetch current quota limits
   */
  async fetchQuotaLimits(): Promise<QuotaLimits> {
    try {
      // Make a minimal API call to get rate limit headers
      const response = await this.client.post('/v1/messages', {
        model: 'claude-3-haiku-20240307',
        max_tokens: 1,
        messages: [{ role: 'user', content: 'ping' }],
      });

      return this.parseRateLimitHeaders(response.headers as Record<string, string>);
    } catch (error: any) {
      // Even on error, we can still get rate limit headers
      if (error.response?.headers) {
        return this.parseRateLimitHeaders(error.response.headers);
      }
      throw new Error(`Failed to fetch quota limits: ${error.message}`);
    }
  }

  /**
   * Fetch subscription metadata
   */
  async fetchSubscriptionMetadata(): Promise<SubscriptionMetadata> {
    // Note: This is a placeholder as the actual endpoint may vary
    // In production, this would call the appropriate API endpoint
    try {
      // Simulated subscription data based on API key characteristics
      return {
        subscriptionTier: 'Pro', // This would come from actual API
        features: ['claude-3-opus', 'claude-3-sonnet', 'claude-3-haiku'],
      };
    } catch (error: any) {
      throw new Error(`Failed to fetch subscription metadata: ${error.message}`);
    }
  }

  /**
   * Test API connectivity
   */
  async testConnection(): Promise<boolean> {
    try {
      await this.fetchQuotaLimits();
      return true;
    } catch {
      return false;
    }
  }
}
