/**
 * Example: Using Claude Code Statusline Programmatically
 * 
 * This example demonstrates how to integrate the statusline library
 * into your Node.js application.
 */

import { QuotaMonitor, StatuslineConfig } from 'claude-code-statusline';

// Example 1: Basic monitoring
async function basicMonitoring() {
  const config: StatuslineConfig = {
    theme: 'default',
    progressStyle: 'basic',
    layout: 'compact',
    updateInterval: 5000,
    enableDebug: false,
    enableTelemetry: true,
  };

  const monitor = new QuotaMonitor(process.env.CLAUDE_API_KEY!, config);
  
  // Start continuous monitoring
  await monitor.start();
  
  // Stop after 30 seconds
  setTimeout(() => {
    monitor.stop();
    console.log('Monitoring stopped.');
    process.exit(0);
  }, 30000);
}

// Example 2: One-time status check
async function oneTimeCheck() {
  const config: StatuslineConfig = {
    theme: 'colorful',
    progressStyle: 'gradient',
    layout: 'detailed',
    updateInterval: 5000,
    enableDebug: false,
    enableTelemetry: false,
  };

  const monitor = new QuotaMonitor(process.env.CLAUDE_API_KEY!, config);
  
  try {
    const status = await monitor.getStatus();
    
    console.log('Current Quota Status:');
    console.log('5-Hour Limit:', status.quotaLimits.fiveHour);
    console.log('7-Day Limit:', status.quotaLimits.sevenDay);
    console.log('Subscription:', status.subscription);
    console.log('Warnings:', status.warnings);
  } catch (error) {
    console.error('Error fetching status:', error);
  }
}

// Example 3: Custom warning handling
async function customWarningHandling() {
  const config: StatuslineConfig = {
    theme: 'dark',
    progressStyle: 'blocks',
    layout: 'full',
    updateInterval: 10000,
    enableDebug: true,
    enableTelemetry: true,
  };

  const monitor = new QuotaMonitor(process.env.CLAUDE_API_KEY!, config);
  
  // Custom check with warning handling
  const status = await monitor.getStatus();
  
  status.warnings.forEach(warning => {
    if (warning.level === 'critical') {
      console.error('CRITICAL WARNING:', warning.message);
      // Send alert, pause operations, etc.
    } else if (warning.level === 'warning') {
      console.warn('Warning:', warning.message);
      // Log to monitoring system
    }
  });
}

// Example 4: Exporting analytics
function exportAnalytics() {
  const config: StatuslineConfig = {
    theme: 'default',
    progressStyle: 'basic',
    layout: 'compact',
    updateInterval: 5000,
    enableDebug: false,
    enableTelemetry: true,
  };

  const monitor = new QuotaMonitor(
    process.env.CLAUDE_API_KEY!,
    config,
    undefined,
    './logs' // Log directory
  );
  
  // Export last 7 days of data
  const endDate = new Date();
  const startDate = new Date();
  startDate.setDate(startDate.getDate() - 7);
  
  monitor.exportAnalytics(startDate, endDate, './analytics-report.json');
  console.log('Analytics exported to ./analytics-report.json');
}

// Example 5: Dynamic configuration updates
async function dynamicConfiguration() {
  const config: StatuslineConfig = {
    theme: 'minimal',
    progressStyle: 'basic',
    layout: 'minimal',
    updateInterval: 5000,
    enableDebug: false,
    enableTelemetry: true,
  };

  const monitor = new QuotaMonitor(process.env.CLAUDE_API_KEY!, config);
  
  // Start with minimal layout
  await monitor.start();
  
  // Switch to detailed layout after 10 seconds
  setTimeout(() => {
    monitor.updateConfig({
      layout: 'detailed',
      progressStyle: 'gradient',
    });
    console.log('Updated to detailed layout');
  }, 10000);
  
  // Switch to full layout after 20 seconds
  setTimeout(() => {
    monitor.updateConfig({
      layout: 'full',
      theme: 'colorful',
    });
    console.log('Updated to full layout with colorful theme');
  }, 20000);
  
  // Stop after 30 seconds
  setTimeout(() => {
    monitor.stop();
    process.exit(0);
  }, 30000);
}

// Example 6: Testing API connection
async function testConnection() {
  const config: StatuslineConfig = {
    theme: 'default',
    progressStyle: 'basic',
    layout: 'compact',
    updateInterval: 5000,
    enableDebug: false,
    enableTelemetry: false,
  };

  const monitor = new QuotaMonitor(process.env.CLAUDE_API_KEY!, config);
  
  const isConnected = await monitor.testConnection();
  
  if (isConnected) {
    console.log('✓ Successfully connected to Claude API');
  } else {
    console.error('✗ Failed to connect to Claude API');
  }
}

// Run examples (uncomment the one you want to try)
// basicMonitoring();
// oneTimeCheck();
// customWarningHandling();
// exportAnalytics();
// dynamicConfiguration();
// testConnection();
