import { QuotaLimits, QuotaWarning } from '../types';

/**
 * Analyze quota limits and generate warnings
 */
export function analyzeQuotaWarnings(quotaLimits: QuotaLimits): QuotaWarning[] {
  const warnings: QuotaWarning[] = [];

  // Check 5-hour limit
  const fiveHourWarning = checkRateLimit(
    quotaLimits.fiveHour,
    'fiveHour',
    '5-hour'
  );
  if (fiveHourWarning) {
    warnings.push(fiveHourWarning);
  }

  // Check 7-day limit
  const sevenDayWarning = checkRateLimit(
    quotaLimits.sevenDay,
    'sevenDay',
    '7-day'
  );
  if (sevenDayWarning) {
    warnings.push(sevenDayWarning);
  }

  return warnings;
}

/**
 * Check individual rate limit
 */
function checkRateLimit(
  limit: any,
  type: 'fiveHour' | 'sevenDay',
  label: string
): QuotaWarning | null {
  if (limit.percentage >= 95) {
    return {
      level: 'critical',
      message: `${label} quota is at ${limit.percentage.toFixed(1)}% capacity! Only ${limit.remaining} requests remaining.`,
      limit,
      type,
    };
  } else if (limit.percentage >= 85) {
    return {
      level: 'warning',
      message: `${label} quota is at ${limit.percentage.toFixed(1)}% capacity. ${limit.remaining} requests remaining.`,
      limit,
      type,
    };
  } else if (limit.percentage >= 75) {
    return {
      level: 'info',
      message: `${label} quota usage: ${limit.percentage.toFixed(1)}%`,
      limit,
      type,
    };
  }
  return null;
}

/**
 * Format duration in human-readable format
 */
export function formatDuration(ms: number): string {
  const seconds = Math.floor(ms / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (days > 0) {
    return `${days}d ${hours % 24}h`;
  } else if (hours > 0) {
    return `${hours}h ${minutes % 60}m`;
  } else if (minutes > 0) {
    return `${minutes}m ${seconds % 60}s`;
  }
  return `${seconds}s`;
}

/**
 * Format bytes in human-readable format
 */
export function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 Bytes';
  
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  
  return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
}

/**
 * Validate API key format
 */
export function validateApiKey(apiKey: string): boolean {
  // Basic validation - real validation would be more sophisticated
  return apiKey.length > 0 && apiKey.startsWith('sk-');
}

/**
 * Sleep utility
 */
export function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Parse environment configuration
 */
export function parseEnvConfig() {
  return {
    apiKey: process.env.CLAUDE_API_KEY || '',
    apiBaseUrl: process.env.CLAUDE_API_BASE_URL || 'https://api.anthropic.com',
    defaultTheme: process.env.DEFAULT_THEME || 'default',
    defaultProgressStyle: process.env.DEFAULT_PROGRESS_STYLE || 'basic',
    updateInterval: parseInt(process.env.UPDATE_INTERVAL || '5000', 10),
    enableDebug: process.env.ENABLE_DEBUG === 'true',
    enableTelemetry: process.env.ENABLE_TELEMETRY !== 'false',
    logDir: process.env.LOG_DIR || './logs',
    logLevel: process.env.LOG_LEVEL || 'info',
  };
}
