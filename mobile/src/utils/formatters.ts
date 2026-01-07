import { formatDistanceToNow, format, parseISO } from 'date-fns';

/**
 * Format date to relative time (e.g., "2 hours ago")
 */
export function formatRelativeTime(date: string | Date): string {
  try {
    const dateObj = typeof date === 'string' ? parseISO(date) : date;
    return formatDistanceToNow(dateObj, { addSuffix: true });
  } catch (error) {
    return 'Unknown';
  }
}

/**
 * Format date to short format (e.g., "Jan 15, 2024")
 */
export function formatShortDate(date: string | Date): string {
  try {
    const dateObj = typeof date === 'string' ? parseISO(date) : date;
    return format(dateObj, 'MMM dd, yyyy');
  } catch (error) {
    return 'Unknown';
  }
}

/**
 * Format date to long format (e.g., "January 15, 2024 2:30 PM")
 */
export function formatLongDate(date: string | Date): string {
  try {
    const dateObj = typeof date === 'string' ? parseISO(date) : date;
    return format(dateObj, 'MMMM dd, yyyy h:mm a');
  } catch (error) {
    return 'Unknown';
  }
}

/**
 * Format number as currency
 */
export function formatCurrency(amount: number, currency: string = 'USD'): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
  }).format(amount);
}

/**
 * Format number with thousands separator
 */
export function formatNumber(num: number): string {
  return new Intl.NumberFormat('en-US').format(num);
}

/**
 * Format percentage
 */
export function formatPercentage(value: number, decimals: number = 1): string {
  return `${(value * 100).toFixed(decimals)}%`;
}

/**
 * Format email for display (mask part of email)
 */
export function formatEmailDisplay(email: string): string {
  const [localPart, domain] = email.split('@');
  const maskedLocal = localPart.substring(0, 2) + '***' + localPart.substring(localPart.length - 1);
  return `${maskedLocal}@${domain}`;
}

/**
 * Format contact count
 */
export function formatContactCount(count: number): string {
  if (count >= 1000000) {
    return `${(count / 1000000).toFixed(1)}M`;
  }
  if (count >= 1000) {
    return `${(count / 1000).toFixed(1)}K`;
  }
  return count.toString();
}

/**
 * Truncate text to specified length
 */
export function truncateText(text: string, length: number = 50): string {
  if (text.length > length) {
    return text.substring(0, length) + '...';
  }
  return text;
}

/**
 * Format campaign status to display format
 */
export function formatCampaignStatus(status: string): {
  label: string;
  color: string;
  icon: string;
} {
  const statusMap: Record<string, { label: string; color: string; icon: string }> = {
    draft: { label: 'Draft', color: '#999', icon: 'edit' },
    scheduled: { label: 'Scheduled', color: '#4A90E2', icon: 'calendar' },
    in_progress: { label: 'In Progress', color: '#F5A623', icon: 'play' },
    completed: { label: 'Completed', color: '#7ED321', icon: 'check' },
    paused: { label: 'Paused', color: '#D0021B', icon: 'pause' },
    stopped: { label: 'Stopped', color: '#555', icon: 'stop' },
  };
  return statusMap[status] || { label: status, color: '#999', icon: 'info' };
}

/**
 * Format contact status
 */
export function formatContactStatus(status: string): {
  label: string;
  color: string;
} {
  const statusMap: Record<string, { label: string; color: string }> = {
    active: { label: 'Active', color: '#7ED321' },
    inactive: { label: 'Inactive', color: '#999' },
    unsubscribed: { label: 'Unsubscribed', color: '#D0021B' },
  };
  return statusMap[status] || { label: status, color: '#999' };
}

/**
 * Format file size
 */
export function formatFileSize(bytes: number): string {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
}

/**
 * Format duration in seconds to time string
 */
export function formatDuration(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;

  const parts: string[] = [];
  if (hours > 0) parts.push(`${hours}h`);
  if (minutes > 0) parts.push(`${minutes}m`);
  if (secs > 0 || parts.length === 0) parts.push(`${secs}s`);

  return parts.join(' ');
}
