import { getTheme, getWarningColor, applyThemeColor } from '../ui/themes';

describe('Themes', () => {
  describe('getTheme', () => {
    it('should return default theme', () => {
      const theme = getTheme('default');
      expect(theme.name).toBe('Default');
      expect(theme.colors).toBeDefined();
      expect(theme.colors.success).toBeDefined();
    });

    it('should return minimal theme', () => {
      const theme = getTheme('minimal');
      expect(theme.name).toBe('Minimal');
    });

    it('should return colorful theme', () => {
      const theme = getTheme('colorful');
      expect(theme.name).toBe('Colorful');
    });

    it('should return dark theme', () => {
      const theme = getTheme('dark');
      expect(theme.name).toBe('Dark');
    });

    it('should return light theme', () => {
      const theme = getTheme('light');
      expect(theme.name).toBe('Light');
    });
  });

  describe('getWarningColor', () => {
    it('should return danger color for 90%+', () => {
      const color = getWarningColor(95, 'default');
      const theme = getTheme('default');
      expect(color).toBe(theme.colors.danger);
    });

    it('should return warning color for 75-89%', () => {
      const color = getWarningColor(80, 'default');
      const theme = getTheme('default');
      expect(color).toBe(theme.colors.warning);
    });

    it('should return success color for <75%', () => {
      const color = getWarningColor(50, 'default');
      const theme = getTheme('default');
      expect(color).toBe(theme.colors.success);
    });
  });

  describe('applyThemeColor', () => {
    it('should apply theme color to text', () => {
      const text = 'Test';
      const result = applyThemeColor(text, 'success', 'default');
      expect(result).toContain(text);
    });
  });
});
