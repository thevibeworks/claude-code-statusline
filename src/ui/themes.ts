import chalk from 'chalk';
import { ThemeConfig, ThemePreset } from '../types';

/**
 * Theme configurations for the statusline
 */
export const themes: Record<ThemePreset, ThemeConfig> = {
  default: {
    name: 'Default',
    colors: {
      success: '#10b981',
      warning: '#f59e0b',
      danger: '#ef4444',
      info: '#3b82f6',
      primary: '#8b5cf6',
      secondary: '#6b7280',
    },
  },
  minimal: {
    name: 'Minimal',
    colors: {
      success: '#ffffff',
      warning: '#ffffff',
      danger: '#ffffff',
      info: '#ffffff',
      primary: '#ffffff',
      secondary: '#808080',
    },
  },
  colorful: {
    name: 'Colorful',
    colors: {
      success: '#00ff00',
      warning: '#ffff00',
      danger: '#ff0000',
      info: '#00ffff',
      primary: '#ff00ff',
      secondary: '#ffa500',
    },
  },
  dark: {
    name: 'Dark',
    colors: {
      success: '#059669',
      warning: '#d97706',
      danger: '#dc2626',
      info: '#2563eb',
      primary: '#7c3aed',
      secondary: '#4b5563',
    },
  },
  light: {
    name: 'Light',
    colors: {
      success: '#86efac',
      warning: '#fcd34d',
      danger: '#fca5a5',
      info: '#93c5fd',
      primary: '#c4b5fd',
      secondary: '#d1d5db',
    },
  },
};

/**
 * Get theme configuration
 */
export function getTheme(preset: ThemePreset): ThemeConfig {
  return themes[preset] || themes.default;
}

/**
 * Apply color based on theme
 */
export function applyThemeColor(
  text: string,
  colorKey: keyof ThemeConfig['colors'],
  theme: ThemePreset
): string {
  const themeConfig = getTheme(theme);
  return chalk.hex(themeConfig.colors[colorKey])(text);
}

/**
 * Get warning color based on percentage
 */
export function getWarningColor(percentage: number, theme: ThemePreset): string {
  const themeConfig = getTheme(theme);
  if (percentage >= 90) {
    return themeConfig.colors.danger;
  } else if (percentage >= 75) {
    return themeConfig.colors.warning;
  }
  return themeConfig.colors.success;
}
