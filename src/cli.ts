#!/usr/bin/env node
import { Command } from 'commander';
import dotenv from 'dotenv';
import chalk from 'chalk';
import { QuotaMonitor } from './monitor';
import { StatuslineConfig, ThemePreset, ProgressBarStyle, LayoutType } from './types';
import { validateApiKey, parseEnvConfig } from './utils/helpers';

// Load environment variables
dotenv.config();

const program = new Command();

program
  .name('claude-statusline')
  .description('Real-time quota monitoring and usage telemetry for Claude Code CLI')
  .version('1.0.0');

program
  .command('monitor')
  .description('Start real-time quota monitoring')
  .option('-k, --api-key <key>', 'Claude API key')
  .option('-t, --theme <theme>', 'Theme preset (default, minimal, colorful, dark, light)', 'default')
  .option('-s, --style <style>', 'Progress bar style', 'basic')
  .option('-l, --layout <layout>', 'Layout type (compact, detailed, minimal, full)', 'compact')
  .option('-i, --interval <ms>', 'Update interval in milliseconds', '5000')
  .option('--debug', 'Enable debug mode')
  .option('--no-telemetry', 'Disable telemetry logging')
  .action(async (options) => {
    const envConfig = parseEnvConfig();
    const apiKey = options.apiKey || envConfig.apiKey;

    if (!apiKey) {
      console.error(chalk.red('Error: API key is required. Provide via --api-key or CLAUDE_API_KEY environment variable.'));
      process.exit(1);
    }

    if (!validateApiKey(apiKey)) {
      console.error(chalk.red('Error: Invalid API key format.'));
      process.exit(1);
    }

    const config: StatuslineConfig = {
      theme: options.theme as ThemePreset || envConfig.defaultTheme as ThemePreset,
      progressStyle: options.style as ProgressBarStyle || envConfig.defaultProgressStyle as ProgressBarStyle,
      layout: options.layout as LayoutType || 'compact',
      updateInterval: parseInt(options.interval, 10) || envConfig.updateInterval,
      enableDebug: options.debug || envConfig.enableDebug,
      enableTelemetry: options.telemetry !== false && envConfig.enableTelemetry,
    };

    const monitor = new QuotaMonitor(apiKey, config, envConfig.apiBaseUrl, envConfig.logDir);

    console.log(chalk.cyan('Starting Claude Code Statusline...'));
    console.log(chalk.dim(`Theme: ${config.theme} | Style: ${config.progressStyle} | Layout: ${config.layout}`));
    console.log(chalk.dim(`Update interval: ${config.updateInterval}ms\n`));

    // Test connection first
    const connected = await monitor.testConnection();
    if (!connected) {
      console.error(chalk.red('Error: Failed to connect to Claude API. Check your API key and network connection.'));
      process.exit(1);
    }

    await monitor.start();

    // Handle graceful shutdown
    process.on('SIGINT', () => {
      console.log(chalk.yellow('\n\nStopping monitor...'));
      monitor.stop();
      process.exit(0);
    });
  });

program
  .command('status')
  .description('Get current quota status (one-time check)')
  .option('-k, --api-key <key>', 'Claude API key')
  .option('-t, --theme <theme>', 'Theme preset', 'default')
  .option('-l, --layout <layout>', 'Layout type', 'detailed')
  .action(async (options) => {
    const envConfig = parseEnvConfig();
    const apiKey = options.apiKey || envConfig.apiKey;

    if (!apiKey) {
      console.error(chalk.red('Error: API key is required.'));
      process.exit(1);
    }

    const config: StatuslineConfig = {
      theme: options.theme as ThemePreset,
      progressStyle: 'basic' as ProgressBarStyle,
      layout: options.layout as LayoutType,
      updateInterval: 5000,
      enableDebug: false,
      enableTelemetry: false,
    };

    const monitor = new QuotaMonitor(apiKey, config, envConfig.apiBaseUrl);
    
    try {
      const status = await monitor.getStatus();
      const renderer = new (await import('./ui/renderer')).StatuslineRenderer(config);
      console.log(renderer.render(status.quotaLimits, status.subscription, status.warnings));
    } catch (error: any) {
      console.error(chalk.red(`Error: ${error.message}`));
      process.exit(1);
    }
  });

program
  .command('export')
  .description('Export usage analytics')
  .option('-k, --api-key <key>', 'Claude API key')
  .option('-s, --start <date>', 'Start date (YYYY-MM-DD)', new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().split('T')[0])
  .option('-e, --end <date>', 'End date (YYYY-MM-DD)', new Date().toISOString().split('T')[0])
  .option('-o, --output <path>', 'Output file path', './analytics.json')
  .action((options) => {
    const envConfig = parseEnvConfig();
    const apiKey = options.apiKey || envConfig.apiKey;

    if (!apiKey) {
      console.error(chalk.red('Error: API key is required.'));
      process.exit(1);
    }

    const config: StatuslineConfig = {
      theme: 'default',
      progressStyle: 'basic',
      layout: 'compact',
      updateInterval: 5000,
      enableDebug: false,
      enableTelemetry: true,
    };

    const monitor = new QuotaMonitor(apiKey, config, envConfig.apiBaseUrl, envConfig.logDir);
    const startDate = new Date(options.start);
    const endDate = new Date(options.end);

    console.log(chalk.cyan(`Exporting analytics from ${startDate.toLocaleDateString()} to ${endDate.toLocaleDateString()}...`));
    
    monitor.exportAnalytics(startDate, endDate, options.output);
    
    console.log(chalk.green(`✓ Analytics exported to ${options.output}`));
  });

program
  .command('test')
  .description('Test API connection')
  .option('-k, --api-key <key>', 'Claude API key')
  .action(async (options) => {
    const envConfig = parseEnvConfig();
    const apiKey = options.apiKey || envConfig.apiKey;

    if (!apiKey) {
      console.error(chalk.red('Error: API key is required.'));
      process.exit(1);
    }

    const config: StatuslineConfig = {
      theme: 'default',
      progressStyle: 'basic',
      layout: 'compact',
      updateInterval: 5000,
      enableDebug: false,
      enableTelemetry: false,
    };

    const monitor = new QuotaMonitor(apiKey, config, envConfig.apiBaseUrl);
    
    console.log(chalk.cyan('Testing API connection...'));
    const connected = await monitor.testConnection();
    
    if (connected) {
      console.log(chalk.green('✓ Successfully connected to Claude API'));
    } else {
      console.log(chalk.red('✗ Failed to connect to Claude API'));
      process.exit(1);
    }
  });

// Parse command line arguments
program.parse();
