import cliProgress from 'cli-progress';
import chalk from 'chalk';
import { ProgressBarStyle } from '../types';

/**
 * Progress bar style configurations
 */
export const progressBarStyles: Record<ProgressBarStyle, any> = {
  basic: {
    format: '{bar} | {percentage}% | {value}/{total}',
    barCompleteChar: '\u2588',
    barIncompleteChar: '\u2591',
    hideCursor: true,
  },
  shades: {
    format: '{bar} | {percentage}% | {value}/{total}',
    barCompleteChar: '\u2593',
    barIncompleteChar: '\u2591',
    hideCursor: true,
  },
  rect: {
    format: '[{bar}] {percentage}% | {value}/{total}',
    barCompleteChar: '=',
    barIncompleteChar: '-',
    hideCursor: true,
  },
  legacy: {
    format: 'Progress [{bar}] {percentage}% | ETA: {eta}s',
    barCompleteChar: '#',
    barIncompleteChar: '.',
    hideCursor: true,
  },
  circle: {
    format: '{bar} {percentage}% | {value}/{total}',
    barCompleteChar: '\u25cf',
    barIncompleteChar: '\u25cb',
    hideCursor: true,
  },
  gradient: {
    format: '{bar} | {percentage}% | {value}/{total}',
    barCompleteChar: '\u2588',
    barIncompleteChar: '\u2591',
    hideCursor: true,
  },
  arrow: {
    format: '{bar} {percentage}% | {value}/{total}',
    barCompleteChar: '>',
    barIncompleteChar: '-',
    hideCursor: true,
  },
  dots: {
    format: '{bar} {percentage}% | {value}/{total}',
    barCompleteChar: '\u2022',
    barIncompleteChar: '\u00b7',
    hideCursor: true,
  },
  blocks: {
    format: '{bar} {percentage}% | {value}/{total}',
    barCompleteChar: '\u2589',
    barIncompleteChar: '\u2581',
    hideCursor: true,
  },
};

/**
 * Create a progress bar with specified style
 */
export function createProgressBar(style: ProgressBarStyle): cliProgress.SingleBar {
  const config = progressBarStyles[style] || progressBarStyles.basic;
  return new cliProgress.SingleBar(config, cliProgress.Presets.shades_classic);
}

/**
 * Format progress bar for inline display
 */
export function formatProgressBar(
  percentage: number,
  style: ProgressBarStyle,
  width: number = 20
): string {
  const config = progressBarStyles[style] || progressBarStyles.basic;
  const filled = Math.round((percentage / 100) * width);
  const empty = width - filled;
  
  const filledBar = config.barCompleteChar.repeat(filled);
  const emptyBar = config.barIncompleteChar.repeat(empty);
  
  return `${filledBar}${emptyBar}`;
}

/**
 * Get color for progress percentage
 */
export function getProgressColor(percentage: number): (text: string) => string {
  if (percentage >= 90) {
    return chalk.red;
  } else if (percentage >= 75) {
    return chalk.yellow;
  } else if (percentage >= 50) {
    return chalk.blue;
  }
  return chalk.green;
}
