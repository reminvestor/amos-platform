import { useAppSelector } from '@store';
import { getColors } from '@theme/colors';

/**
 * Hook to get current theme colors
 * Use this in any screen/component to get theme-aware colors
 */
export function useThemeColors() {
  const { theme } = useAppSelector((state) => state.ui);
  return getColors(theme);
}

export default useThemeColors;
