export interface DateRange {
  startDate: Date;
  endDate: Date;
  label: string;
}

export const getDateRangePresets = (): Record<string, DateRange> => {
  const today = new Date();
  const now = new Date();

  // This Week
  const dayOfWeek = today.getDay();
  const weekStart = new Date(today);
  weekStart.setDate(today.getDate() - dayOfWeek);
  weekStart.setHours(0, 0, 0, 0);

  const weekEnd = new Date(weekStart);
  weekEnd.setDate(weekStart.getDate() + 6);
  weekEnd.setHours(23, 59, 59, 999);

  // This Month
  const monthStart = new Date(today.getFullYear(), today.getMonth(), 1);
  monthStart.setHours(0, 0, 0, 0);

  const monthEnd = new Date(today.getFullYear(), today.getMonth() + 1, 0);
  monthEnd.setHours(23, 59, 59, 999);

  // Last 30 Days
  const thirtyDaysAgo = new Date(now);
  thirtyDaysAgo.setDate(now.getDate() - 30);
  thirtyDaysAgo.setHours(0, 0, 0, 0);

  const last30End = new Date(now);
  last30End.setHours(23, 59, 59, 999);

  // Last 90 Days
  const ninetyDaysAgo = new Date(now);
  ninetyDaysAgo.setDate(now.getDate() - 90);
  ninetyDaysAgo.setHours(0, 0, 0, 0);

  const last90End = new Date(now);
  last90End.setHours(23, 59, 59, 999);

  // All Time
  const allTimeStart = new Date(2020, 0, 1);
  allTimeStart.setHours(0, 0, 0, 0);

  const allTimeEnd = new Date();
  allTimeEnd.setHours(23, 59, 59, 999);

  return {
    thisWeek: {
      startDate: weekStart,
      endDate: weekEnd,
      label: 'This Week',
    },
    thisMonth: {
      startDate: monthStart,
      endDate: monthEnd,
      label: 'This Month',
    },
    last30Days: {
      startDate: thirtyDaysAgo,
      endDate: last30End,
      label: 'Last 30 Days',
    },
    last90Days: {
      startDate: ninetyDaysAgo,
      endDate: last90End,
      label: 'Last 90 Days',
    },
    allTime: {
      startDate: allTimeStart,
      endDate: allTimeEnd,
      label: 'All Time',
    },
  };
};

export const formatDateForAPI = (date: Date): string => {
  return date.toISOString().split('T')[0];
};

export const formatDateRange = (startDate: Date, endDate: Date): string => {
  const start = startDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  const end = endDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  return `${start} - ${end}`;
};

export const isDateInRange = (date: Date, startDate: Date, endDate: Date): boolean => {
  return date >= startDate && date <= endDate;
};
