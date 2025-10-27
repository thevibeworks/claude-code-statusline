#!/usr/bin/env node

/**
 * Demo script to showcase different layouts and styles
 * This uses mock data to demonstrate the UI without requiring an API key
 */

const { StatuslineRenderer } = require('../dist/ui/renderer');
const { analyzeQuotaWarnings } = require('../dist/utils/helpers');

// Mock quota data
const mockQuotaLimits = {
  fiveHour: {
    limit: 500,
    remaining: 50,
    reset: new Date(Date.now() + 2 * 60 * 60 * 1000), // 2 hours from now
    used: 450,
    percentage: 90,
  },
  sevenDay: {
    limit: 3000,
    remaining: 200,
    reset: new Date(Date.now() + 4 * 24 * 60 * 60 * 1000), // 4 days from now
    used: 2800,
    percentage: 93.3,
  },
};

const mockSubscription = {
  subscriptionTier: 'Pro',
  features: ['claude-3-opus', 'claude-3-sonnet', 'claude-3-haiku'],
};

const warnings = analyzeQuotaWarnings(mockQuotaLimits);

// Demo configurations
const demos = [
  { layout: 'compact', style: 'basic', theme: 'default' },
  { layout: 'compact', style: 'gradient', theme: 'colorful' },
  { layout: 'minimal', style: 'basic', theme: 'minimal' },
  { layout: 'detailed', style: 'shades', theme: 'dark' },
  { layout: 'full', style: 'blocks', theme: 'default' },
];

console.log('='.repeat(60));
console.log('Claude Code Statusline - Demo Showcase');
console.log('='.repeat(60));
console.log('');

demos.forEach((demo, index) => {
  const config = {
    theme: demo.theme,
    progressStyle: demo.style,
    layout: demo.layout,
    updateInterval: 5000,
    enableDebug: false,
    enableTelemetry: false,
  };

  const renderer = new StatuslineRenderer(config);
  
  console.log(`\n${index + 1}. Layout: ${demo.layout} | Style: ${demo.style} | Theme: ${demo.theme}`);
  console.log('-'.repeat(60));
  console.log(renderer.render(mockQuotaLimits, mockSubscription, warnings));
  console.log('');
});

console.log('='.repeat(60));
console.log('Progress Bar Styles Demo');
console.log('='.repeat(60));
console.log('');

const styles = ['basic', 'shades', 'rect', 'legacy', 'circle', 'gradient', 'arrow', 'dots', 'blocks'];
const { formatProgressBar } = require('../dist/ui/progressBar');

styles.forEach((style) => {
  const bar = formatProgressBar(75, style, 30);
  console.log(`${style.padEnd(10)}: ${bar} 75%`);
});

console.log('');
console.log('='.repeat(60));
console.log('Demo completed! Use "node dist/cli.js monitor --help" for CLI options.');
console.log('='.repeat(60));
