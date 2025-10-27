/**
 * Core types for Claude Code Statusline
 */

export interface QuotaLimits {
  fiveHour: RateLimit;
  sevenDay: RateLimit;
}

export interface RateLimit {
  limit: number;
  remaining: number;
  reset: Date;
  used: number;
  percentage: number;
}

export interface SubscriptionMetadata {
  organizationId?: string;
  subscriptionTier: string;
  billingPeriod?: string;
  features: string[];
}

export interface UsageSnapshot {
  timestamp: Date;
  quotaLimits: QuotaLimits;
  subscription: SubscriptionMetadata;
  costEstimate?: number;
}

export type ProgressBarStyle = 
  | 'basic' 
  | 'shades' 
  | 'rect' 
  | 'legacy' 
  | 'circle' 
  | 'gradient' 
  | 'arrow' 
  | 'dots' 
  | 'blocks';

export type ThemePreset = 'default' | 'minimal' | 'colorful' | 'dark' | 'light';

export interface ThemeConfig {
  name: string;
  colors: {
    success: string;
    warning: string;
    danger: string;
    info: string;
    primary: string;
    secondary: string;
  };
}

export interface StatuslineConfig {
  theme: ThemePreset;
  progressStyle: ProgressBarStyle;
  layout: LayoutType;
  updateInterval: number;
  enableDebug: boolean;
  enableTelemetry: boolean;
}

export type LayoutType = 'compact' | 'detailed' | 'minimal' | 'full';

export interface ApiResponse {
  usage?: {
    input_tokens?: number;
    output_tokens?: number;
  };
  headers?: Record<string, string>;
}

export interface QuotaWarning {
  level: 'info' | 'warning' | 'critical';
  message: string;
  limit: RateLimit;
  type: 'fiveHour' | 'sevenDay';
}
