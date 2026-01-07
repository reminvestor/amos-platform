import {
  formatRelativeTime,
  formatShortDate,
  formatLongDate,
  formatCurrency,
  formatNumber,
  formatPercentage,
  formatEmailDisplay,
  formatContactCount,
  truncateText,
  formatCampaignStatus,
  formatContactStatus,
  formatFileSize,
  formatDuration,
} from '@utils/formatters';

describe('Formatters', () => {
  const testDate = new Date('2024-01-15T10:30:00Z');

  describe('formatRelativeTime', () => {
    it('should format date as relative time', () => {
      const result = formatRelativeTime(testDate);
      expect(result).toMatch(/ago|now/);
    });

    it('should handle invalid dates', () => {
      const result = formatRelativeTime('invalid-date');
      expect(result).toBe('Unknown');
    });
  });

  describe('formatShortDate', () => {
    it('should format date as short format', () => {
      const result = formatShortDate(testDate);
      expect(result).toMatch(/Jan|January/);
      expect(result).toMatch(/2024/);
    });

    it('should handle string dates', () => {
      const result = formatShortDate('2024-01-15');
      expect(result).toContain('2024');
    });
  });

  describe('formatLongDate', () => {
    it('should format date as long format', () => {
      const result = formatLongDate(testDate);
      expect(result).toMatch(/January|Jan/);
      expect(result).toMatch(/2024/);
      expect(result).toMatch(/AM|PM/);
    });
  });

  describe('formatCurrency', () => {
    it('should format number as currency', () => {
      const result = formatCurrency(1234.56);
      expect(result).toContain('$');
      expect(result).toContain('1');
    });

    it('should handle different currencies', () => {
      const result = formatCurrency(1000, 'EUR');
      expect(result).toContain('€');
    });
  });

  describe('formatNumber', () => {
    it('should add thousands separator', () => {
      expect(formatNumber(1000)).toContain(',');
      expect(formatNumber(1000000)).toContain(',');
    });

    it('should format small numbers', () => {
      expect(formatNumber(100)).not.toContain(',');
    });
  });

  describe('formatPercentage', () => {
    it('should format as percentage', () => {
      expect(formatPercentage(0.5)).toBe('50.0%');
      expect(formatPercentage(0.333, 2)).toBe('33.30%');
    });

    it('should handle zero', () => {
      expect(formatPercentage(0)).toBe('0.0%');
    });

    it('should handle decimals', () => {
      expect(formatPercentage(0.1234)).toMatch('%');
    });
  });

  describe('formatEmailDisplay', () => {
    it('should mask email address', () => {
      const result = formatEmailDisplay('testuser@example.com');
      expect(result).toContain('***');
      expect(result).toContain('@example.com');
      expect(result).not.toContain('testuser');
    });

    it('should show domain', () => {
      const result = formatEmailDisplay('long.email.address@example.com');
      expect(result).toContain('example.com');
    });
  });

  describe('formatContactCount', () => {
    it('should format large numbers as K', () => {
      expect(formatContactCount(1500)).toBe('1.5K');
      expect(formatContactCount(5000)).toBe('5.0K');
    });

    it('should format very large numbers as M', () => {
      expect(formatContactCount(1500000)).toBe('1.5M');
    });

    it('should show raw count for small numbers', () => {
      expect(formatContactCount(500)).toBe('500');
    });
  });

  describe('truncateText', () => {
    it('should truncate long text', () => {
      const long = 'This is a very long text that should be truncated';
      const result = truncateText(long, 20);
      expect(result.length).toBeLessThanOrEqual(23); // 20 + '...'
      expect(result).toContain('...');
    });

    it('should not truncate short text', () => {
      const short = 'Short text';
      const result = truncateText(short, 20);
      expect(result).toBe(short);
      expect(result).not.toContain('...');
    });

    it('should use default length', () => {
      const text = 'x'.repeat(100);
      const result = truncateText(text);
      expect(result.length).toBeLessThanOrEqual(53); // 50 + '...'
    });
  });

  describe('formatCampaignStatus', () => {
    it('should format draft status', () => {
      const result = formatCampaignStatus('draft');
      expect(result.label).toBe('Draft');
      expect(result.color).toBeDefined();
      expect(result.icon).toBeDefined();
    });

    it('should format in_progress status', () => {
      const result = formatCampaignStatus('in_progress');
      expect(result.label).toBe('In Progress');
      expect(result.color).toBeDefined();
    });

    it('should handle unknown status', () => {
      const result = formatCampaignStatus('unknown');
      expect(result.label).toBe('unknown');
    });
  });

  describe('formatContactStatus', () => {
    it('should format active status', () => {
      const result = formatContactStatus('active');
      expect(result.label).toBe('Active');
      expect(result.color).toBeDefined();
    });

    it('should format unsubscribed status', () => {
      const result = formatContactStatus('unsubscribed');
      expect(result.label).toBe('Unsubscribed');
      expect(result.color).toBeDefined();
    });
  });

  describe('formatFileSize', () => {
    it('should format bytes', () => {
      expect(formatFileSize(500)).toContain('Bytes');
    });

    it('should format kilobytes', () => {
      expect(formatFileSize(1024)).toContain('KB');
    });

    it('should format megabytes', () => {
      expect(formatFileSize(1024 * 1024)).toContain('MB');
    });

    it('should format gigabytes', () => {
      expect(formatFileSize(1024 * 1024 * 1024)).toContain('GB');
    });

    it('should handle zero', () => {
      expect(formatFileSize(0)).toBe('0 Bytes');
    });
  });

  describe('formatDuration', () => {
    it('should format seconds', () => {
      expect(formatDuration(30)).toContain('30s');
    });

    it('should format minutes', () => {
      expect(formatDuration(120)).toContain('2m');
    });

    it('should format hours', () => {
      expect(formatDuration(3600)).toContain('1h');
    });

    it('should format combined time', () => {
      const result = formatDuration(3661); // 1h 1m 1s
      expect(result).toContain('h');
      expect(result).toContain('m');
      expect(result).toContain('s');
    });
  });
});
