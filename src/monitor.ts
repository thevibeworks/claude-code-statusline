import { 
  QuotaLimits, 
  SubscriptionMetadata, 
  UsageSnapshot, 
  StatuslineConfig,
  QuotaWarning 
} from './types';
import { ClaudeApiService } from './services/claudeApi';
import { TelemetryService } from './services/telemetry';
import { StatuslineRenderer } from './ui/renderer';
import { analyzeQuotaWarnings, sleep } from './utils/helpers';

/**
 * Main monitor class for quota monitoring
 */
export class QuotaMonitor {
  private apiService: ClaudeApiService;
  private telemetryService: TelemetryService;
  private renderer: StatuslineRenderer;
  private config: StatuslineConfig;
  private isRunning: boolean = false;
  private intervalId?: NodeJS.Timeout;

  constructor(
    apiKey: string,
    config: StatuslineConfig,
    apiBaseUrl?: string,
    logDir?: string
  ) {
    this.apiService = new ClaudeApiService(apiKey, apiBaseUrl);
    this.telemetryService = new TelemetryService(logDir, config.enableTelemetry);
    this.renderer = new StatuslineRenderer(config);
    this.config = config;
  }

  /**
   * Start monitoring
   */
  async start(): Promise<void> {
    if (this.isRunning) {
      throw new Error('Monitor is already running');
    }

    this.isRunning = true;
    
    // Initial update
    await this.update();

    // Set up interval for continuous monitoring
    this.intervalId = setInterval(async () => {
      if (this.isRunning) {
        await this.update();
      }
    }, this.config.updateInterval);
  }

  /**
   * Stop monitoring
   */
  stop(): void {
    this.isRunning = false;
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = undefined;
    }
  }

  /**
   * Perform a single update
   */
  async update(): Promise<void> {
    try {
      const quotaLimits = await this.apiService.fetchQuotaLimits();
      const subscription = await this.apiService.fetchSubscriptionMetadata();
      const warnings = analyzeQuotaWarnings(quotaLimits);

      // Create snapshot
      const snapshot: UsageSnapshot = {
        timestamp: new Date(),
        quotaLimits,
        subscription,
        costEstimate: this.telemetryService.calculateCostEstimate({
          timestamp: new Date(),
          quotaLimits,
          subscription,
        }),
      };

      // Log to telemetry
      this.telemetryService.logSnapshot(snapshot);

      // Render statusline
      this.renderStatus(quotaLimits, subscription, warnings);

      if (this.config.enableDebug) {
        this.logDebugInfo(snapshot, warnings);
      }
    } catch (error: any) {
      console.error(`Error updating quota: ${error.message}`);
      if (this.config.enableDebug) {
        console.error(error.stack);
      }
    }
  }

  /**
   * Render current status
   */
  private renderStatus(
    quotaLimits: QuotaLimits,
    subscription: SubscriptionMetadata,
    warnings: QuotaWarning[]
  ): void {
    if (this.config.layout !== 'minimal') {
      this.renderer.clear();
    }
    const output = this.renderer.render(quotaLimits, subscription, warnings);
    console.log(output);
  }

  /**
   * Log debug information
   */
  private logDebugInfo(snapshot: UsageSnapshot, warnings: QuotaWarning[]): void {
    console.log('\n[DEBUG] Snapshot Details:');
    console.log(JSON.stringify(snapshot, null, 2));
    console.log('\n[DEBUG] Active Warnings:', warnings.length);
  }

  /**
   * Get current quota status (single fetch)
   */
  async getStatus(): Promise<{
    quotaLimits: QuotaLimits;
    subscription: SubscriptionMetadata;
    warnings: QuotaWarning[];
  }> {
    const quotaLimits = await this.apiService.fetchQuotaLimits();
    const subscription = await this.apiService.fetchSubscriptionMetadata();
    const warnings = analyzeQuotaWarnings(quotaLimits);

    return { quotaLimits, subscription, warnings };
  }

  /**
   * Test API connection
   */
  async testConnection(): Promise<boolean> {
    return this.apiService.testConnection();
  }

  /**
   * Update configuration
   */
  updateConfig(config: Partial<StatuslineConfig>): void {
    this.config = { ...this.config, ...config };
    this.renderer.updateConfig(config);
  }

  /**
   * Export analytics
   */
  exportAnalytics(startDate: Date, endDate: Date, outputPath: string): void {
    this.telemetryService.exportAnalytics(startDate, endDate, outputPath);
  }
}
