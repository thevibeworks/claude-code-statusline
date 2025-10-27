import { analyzeQuotaWarnings, validateApiKey, formatDuration, formatBytes } from '../utils/helpers';
import { QuotaLimits } from '../types';

describe('Helpers', () => {
  describe('analyzeQuotaWarnings', () => {
    it('should generate critical warning at 95%+ usage', () => {
      const quotaLimits: QuotaLimits = {
        fiveHour: {
          limit: 100,
          remaining: 4,
          reset: new Date(),
          used: 96,
          percentage: 96,
        },
        sevenDay: {
          limit: 1000,
          remaining: 500,
          reset: new Date(),
          used: 500,
          percentage: 50,
        },
      };

      const warnings = analyzeQuotaWarnings(quotaLimits);
      expect(warnings).toHaveLength(1);
      expect(warnings[0].level).toBe('critical');
      expect(warnings[0].type).toBe('fiveHour');
    });

    it('should generate warning at 85-94% usage', () => {
      const quotaLimits: QuotaLimits = {
        fiveHour: {
          limit: 100,
          remaining: 10,
          reset: new Date(),
          used: 90,
          percentage: 90,
        },
        sevenDay: {
          limit: 1000,
          remaining: 100,
          reset: new Date(),
          used: 900,
          percentage: 90,
        },
      };

      const warnings = analyzeQuotaWarnings(quotaLimits);
      expect(warnings).toHaveLength(2);
      expect(warnings[0].level).toBe('warning');
      expect(warnings[1].level).toBe('warning');
    });

    it('should generate info at 75-84% usage', () => {
      const quotaLimits: QuotaLimits = {
        fiveHour: {
          limit: 100,
          remaining: 20,
          reset: new Date(),
          used: 80,
          percentage: 80,
        },
        sevenDay: {
          limit: 1000,
          remaining: 500,
          reset: new Date(),
          used: 500,
          percentage: 50,
        },
      };

      const warnings = analyzeQuotaWarnings(quotaLimits);
      expect(warnings).toHaveLength(1);
      expect(warnings[0].level).toBe('info');
    });

    it('should not generate warnings below 75%', () => {
      const quotaLimits: QuotaLimits = {
        fiveHour: {
          limit: 100,
          remaining: 50,
          reset: new Date(),
          used: 50,
          percentage: 50,
        },
        sevenDay: {
          limit: 1000,
          remaining: 500,
          reset: new Date(),
          used: 500,
          percentage: 50,
        },
      };

      const warnings = analyzeQuotaWarnings(quotaLimits);
      expect(warnings).toHaveLength(0);
    });
  });

  describe('validateApiKey', () => {
    it('should validate correct API key format', () => {
      expect(validateApiKey('sk-ant-1234567890')).toBe(true);
    });

    it('should reject empty API key', () => {
      expect(validateApiKey('')).toBe(false);
    });

    it('should reject API key without sk- prefix', () => {
      expect(validateApiKey('invalid-key')).toBe(false);
    });
  });

  describe('formatDuration', () => {
    it('should format seconds', () => {
      expect(formatDuration(5000)).toBe('5s');
    });

    it('should format minutes and seconds', () => {
      expect(formatDuration(125000)).toBe('2m 5s');
    });

    it('should format hours and minutes', () => {
      expect(formatDuration(7325000)).toBe('2h 2m');
    });

    it('should format days and hours', () => {
      expect(formatDuration(90000000)).toBe('1d 1h');
    });
  });

  describe('formatBytes', () => {
    it('should format 0 bytes', () => {
      expect(formatBytes(0)).toBe('0 Bytes');
    });

    it('should format bytes', () => {
      expect(formatBytes(512)).toBe('512 Bytes');
    });

    it('should format kilobytes', () => {
      expect(formatBytes(1024)).toBe('1 KB');
    });

    it('should format megabytes', () => {
      expect(formatBytes(1048576)).toBe('1 MB');
    });
  });
});
