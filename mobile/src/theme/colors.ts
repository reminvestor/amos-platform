/**
 * Color palette for light and dark modes
 */

export const colors = {
  light: {
    // Primary colors
    primary: '#007AFF',
    primaryLight: '#E8F4FF',
    primaryDark: '#0051CC',

    // Neutral colors
    background: '#FFFFFF',
    surface: '#F9FAFB',
    border: '#E5E7EB',
    text: '#111827',
    textSecondary: '#6B7280',
    textTertiary: '#9CA3AF',

    // Status colors
    success: '#10B981',
    successLight: '#D1FAE5',
    warning: '#F59E0B',
    warningLight: '#FEF3C7',
    error: '#EF4444',
    errorLight: '#FEE2E2',
    info: '#3B82F6',
    infoLight: '#DBEAFE',

    // Semantic colors
    muted: '#F3F4F6',
    overlay: 'rgba(0, 0, 0, 0.5)',
  },
  dark: {
    // Primary colors
    primary: '#0A84FF',
    primaryLight: '#1E3A8A',
    primaryDark: '#60A5FA',

    // Neutral colors
    background: '#0F172A',
    surface: '#1E293B',
    border: '#334155',
    text: '#F1F5F9',
    textSecondary: '#CBD5E1',
    textTertiary: '#94A3B8',

    // Status colors
    success: '#10B981',
    successLight: '#064E3B',
    warning: '#F59E0B',
    warningLight: '#78350F',
    error: '#F87171',
    errorLight: '#7F1D1D',
    info: '#60A5FA',
    infoLight: '#1E3A8A',

    // Semantic colors
    muted: '#1E293B',
    overlay: 'rgba(0, 0, 0, 0.8)',
  },
};

export type ColorMode = 'light' | 'dark';
export type ColorKey = keyof typeof colors.light;

export const getColors = (theme: ColorMode) => colors[theme];
