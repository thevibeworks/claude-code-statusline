import { formatProgressBar, getProgressColor } from '../ui/progressBar';
import chalk from 'chalk';

describe('ProgressBar', () => {
  describe('formatProgressBar', () => {
    it('should format progress bar at 0%', () => {
      const bar = formatProgressBar(0, 'basic', 10);
      expect(bar.length).toBe(10);
    });

    it('should format progress bar at 50%', () => {
      const bar = formatProgressBar(50, 'basic', 10);
      expect(bar.length).toBe(10);
    });

    it('should format progress bar at 100%', () => {
      const bar = formatProgressBar(100, 'basic', 10);
      expect(bar.length).toBe(10);
    });

    it('should work with different styles', () => {
      const styles = ['basic', 'shades', 'rect', 'legacy', 'circle', 'gradient', 'arrow', 'dots', 'blocks'];
      styles.forEach(style => {
        const bar = formatProgressBar(50, style as any, 20);
        expect(bar.length).toBe(20);
      });
    });
  });

  describe('getProgressColor', () => {
    it('should return red for 90%+', () => {
      const color = getProgressColor(95);
      expect(color).toBe(chalk.red);
    });

    it('should return yellow for 75-89%', () => {
      const color = getProgressColor(80);
      expect(color).toBe(chalk.yellow);
    });

    it('should return blue for 50-74%', () => {
      const color = getProgressColor(60);
      expect(color).toBe(chalk.blue);
    });

    it('should return green for <50%', () => {
      const color = getProgressColor(30);
      expect(color).toBe(chalk.green);
    });
  });
});
