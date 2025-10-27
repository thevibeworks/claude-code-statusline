import fs from 'fs';
import path from 'path';
import { UsageSnapshot } from '../types';

/**
 * Service for logging usage snapshots for analytics
 */
export class TelemetryService {
  private logDir: string;
  private enabled: boolean;

  constructor(logDir: string = './logs', enabled: boolean = true) {
    this.logDir = logDir;
    this.enabled = enabled;
    this.ensureLogDirectory();
  }

  /**
   * Ensure log directory exists
   */
  private ensureLogDirectory(): void {
    if (this.enabled && !fs.existsSync(this.logDir)) {
      fs.mkdirSync(this.logDir, { recursive: true });
    }
  }

  /**
   * Log a usage snapshot
   */
  logSnapshot(snapshot: UsageSnapshot): void {
    if (!this.enabled) {
      return;
    }

    const date = new Date().toISOString().split('T')[0];
    const logFile = path.join(this.logDir, `usage-${date}.jsonl`);
    
    const logEntry = JSON.stringify({
      ...snapshot,
      timestamp: snapshot.timestamp.toISOString(),
    }) + '\n';

    fs.appendFileSync(logFile, logEntry);
  }

  /**
   * Get usage snapshots for a date range
   */
  getSnapshots(startDate: Date, endDate: Date): UsageSnapshot[] {
    if (!this.enabled) {
      return [];
    }

    const snapshots: UsageSnapshot[] = [];
    const currentDate = new Date(startDate);

    while (currentDate <= endDate) {
      const dateStr = currentDate.toISOString().split('T')[0];
      const logFile = path.join(this.logDir, `usage-${dateStr}.jsonl`);

      if (fs.existsSync(logFile)) {
        const content = fs.readFileSync(logFile, 'utf-8');
        const lines = content.trim().split('\n');
        
        for (const line of lines) {
          try {
            const data = JSON.parse(line);
            snapshots.push({
              ...data,
              timestamp: new Date(data.timestamp),
              quotaLimits: {
                fiveHour: {
                  ...data.quotaLimits.fiveHour,
                  reset: new Date(data.quotaLimits.fiveHour.reset),
                },
                sevenDay: {
                  ...data.quotaLimits.sevenDay,
                  reset: new Date(data.quotaLimits.sevenDay.reset),
                },
              },
            });
          } catch (error) {
            console.error(`Error parsing log entry: ${error}`);
          }
        }
      }

      currentDate.setDate(currentDate.getDate() + 1);
    }

    return snapshots;
  }

  /**
   * Calculate cost estimate based on usage
   * Note: Uses 7-day usage only to avoid double-counting,
   * as 5-hour usage is a subset of 7-day usage
   */
  calculateCostEstimate(snapshot: UsageSnapshot): number {
    // Simplified cost calculation
    // Real implementation would use actual pricing tiers and token counts
    const { sevenDay } = snapshot.quotaLimits;
    const baseRate = 0.001; // $0.001 per request (placeholder)
    
    return sevenDay.used * baseRate;
  }

  /**
   * Export analytics data
   */
  exportAnalytics(startDate: Date, endDate: Date, outputPath: string): void {
    const snapshots = this.getSnapshots(startDate, endDate);
    const analytics = {
      period: {
        start: startDate.toISOString(),
        end: endDate.toISOString(),
      },
      totalSnapshots: snapshots.length,
      snapshots,
    };

    fs.writeFileSync(outputPath, JSON.stringify(analytics, null, 2));
  }
}
