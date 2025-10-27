import chalk from 'chalk';
import { 
  QuotaLimits, 
  QuotaWarning, 
  SubscriptionMetadata, 
  StatuslineConfig,
  RateLimit
} from '../types';
import { formatProgressBar, getProgressColor } from './progressBar';

/**
 * Render the statusline with quota information
 */
export class StatuslineRenderer {
  private config: StatuslineConfig;

  constructor(config: StatuslineConfig) {
    this.config = config;
  }

  /**
   * Render complete statusline
   */
  render(
    quotaLimits: QuotaLimits,
    subscription: SubscriptionMetadata,
    warnings: QuotaWarning[]
  ): string {
    switch (this.config.layout) {
      case 'compact':
        return this.renderCompact(quotaLimits);
      case 'detailed':
        return this.renderDetailed(quotaLimits, subscription, warnings);
      case 'minimal':
        return this.renderMinimal(quotaLimits);
      case 'full':
        return this.renderFull(quotaLimits, subscription, warnings);
      default:
        return this.renderCompact(quotaLimits);
    }
  }

  /**
   * Render compact layout
   */
  private renderCompact(quotaLimits: QuotaLimits): string {
    const { fiveHour, sevenDay } = quotaLimits;
    
    const fiveHourBar = formatProgressBar(
      fiveHour.percentage,
      this.config.progressStyle,
      15
    );
    const sevenDayBar = formatProgressBar(
      sevenDay.percentage,
      this.config.progressStyle,
      15
    );

    const fiveHourColor = getProgressColor(fiveHour.percentage);
    const sevenDayColor = getProgressColor(sevenDay.percentage);

    return [
      chalk.bold('Claude API Quota:'),
      `5h: ${fiveHourColor(fiveHourBar)} ${fiveHour.remaining}/${fiveHour.limit}`,
      `7d: ${sevenDayColor(sevenDayBar)} ${sevenDay.remaining}/${sevenDay.limit}`,
    ].join(' | ');
  }

  /**
   * Render minimal layout
   */
  private renderMinimal(quotaLimits: QuotaLimits): string {
    const { fiveHour, sevenDay } = quotaLimits;
    return `5h:${fiveHour.remaining}/${fiveHour.limit} 7d:${sevenDay.remaining}/${sevenDay.limit}`;
  }

  /**
   * Render detailed layout
   */
  private renderDetailed(
    quotaLimits: QuotaLimits,
    subscription: SubscriptionMetadata,
    warnings: QuotaWarning[]
  ): string {
    const lines: string[] = [];
    
    lines.push(chalk.bold.cyan('╔═══ Claude API Status ═══╗'));
    lines.push('');
    
    // Subscription info
    lines.push(chalk.bold('Subscription: ') + subscription.subscriptionTier);
    if (subscription.organizationId) {
      lines.push(chalk.dim(`Org: ${subscription.organizationId}`));
    }
    lines.push('');
    
    // 5-hour quota
    lines.push(chalk.bold('5-Hour Quota:'));
    lines.push(this.renderRateLimit(quotaLimits.fiveHour));
    lines.push('');
    
    // 7-day quota
    lines.push(chalk.bold('7-Day Quota:'));
    lines.push(this.renderRateLimit(quotaLimits.sevenDay));
    
    // Warnings
    if (warnings.length > 0) {
      lines.push('');
      lines.push(chalk.bold.yellow('⚠ Warnings:'));
      warnings.forEach(w => {
        const icon = w.level === 'critical' ? '🔴' : w.level === 'warning' ? '⚠️' : 'ℹ️';
        lines.push(`  ${icon} ${w.message}`);
      });
    }
    
    lines.push('');
    lines.push(chalk.bold.cyan('╚════════════════════════╝'));
    
    return lines.join('\n');
  }

  /**
   * Render full layout
   */
  private renderFull(
    quotaLimits: QuotaLimits,
    subscription: SubscriptionMetadata,
    warnings: QuotaWarning[]
  ): string {
    const lines: string[] = [];
    
    lines.push(chalk.bold.magenta('┌─────────────────────────────────────────┐'));
    lines.push(chalk.bold.magenta('│      Claude Code Statusline v1.0        │'));
    lines.push(chalk.bold.magenta('└─────────────────────────────────────────┘'));
    lines.push('');
    
    // Subscription details
    lines.push(chalk.bold.cyan('📊 Subscription Information:'));
    lines.push(`   Tier: ${chalk.green(subscription.subscriptionTier)}`);
    if (subscription.organizationId) {
      lines.push(`   Organization: ${chalk.dim(subscription.organizationId)}`);
    }
    lines.push(`   Features: ${subscription.features.join(', ')}`);
    lines.push('');
    
    // 5-hour quota with details
    lines.push(chalk.bold.cyan('⏱️  5-Hour Rate Limit:'));
    lines.push(this.renderDetailedRateLimit(quotaLimits.fiveHour));
    lines.push('');
    
    // 7-day quota with details
    lines.push(chalk.bold.cyan('📅 7-Day Rate Limit:'));
    lines.push(this.renderDetailedRateLimit(quotaLimits.sevenDay));
    lines.push('');
    
    // Warnings section
    if (warnings.length > 0) {
      lines.push(chalk.bold.yellow('⚠️  Active Warnings:'));
      warnings.forEach(w => {
        const levelColor = w.level === 'critical' ? chalk.red : 
                          w.level === 'warning' ? chalk.yellow : chalk.blue;
        lines.push(levelColor(`   • [${w.level.toUpperCase()}] ${w.message}`));
      });
      lines.push('');
    }
    
    // Footer
    lines.push(chalk.dim('─'.repeat(45)));
    lines.push(chalk.dim(`Last updated: ${new Date().toLocaleTimeString()}`));
    
    return lines.join('\n');
  }

  /**
   * Render rate limit information
   */
  private renderRateLimit(limit: RateLimit): string {
    const bar = formatProgressBar(limit.percentage, this.config.progressStyle, 25);
    const color = getProgressColor(limit.percentage);
    
    return [
      `  ${color(bar)}`,
      `  Used: ${limit.used}/${limit.limit} (${limit.percentage.toFixed(1)}%)`,
      `  Remaining: ${limit.remaining}`,
      `  Resets: ${limit.reset.toLocaleString()}`,
    ].join('\n');
  }

  /**
   * Render detailed rate limit
   */
  private renderDetailedRateLimit(limit: RateLimit): string {
    const bar = formatProgressBar(limit.percentage, this.config.progressStyle, 30);
    const color = getProgressColor(limit.percentage);
    
    const resetTime = limit.reset.getTime() - Date.now();
    const hoursUntilReset = Math.floor(resetTime / (1000 * 60 * 60));
    const minutesUntilReset = Math.floor((resetTime % (1000 * 60 * 60)) / (1000 * 60));
    
    return [
      `   ${color(bar)} ${limit.percentage.toFixed(1)}%`,
      `   Used: ${chalk.bold(limit.used.toString())} | Remaining: ${chalk.bold(limit.remaining.toString())} | Total: ${limit.limit}`,
      `   Resets in: ${hoursUntilReset}h ${minutesUntilReset}m`,
    ].join('\n');
  }

  /**
   * Clear console
   */
  clear(): void {
    console.clear();
  }

  /**
   * Update configuration
   */
  updateConfig(config: Partial<StatuslineConfig>): void {
    this.config = { ...this.config, ...config };
  }
}
