import React from 'react';
import { TouchableOpacity, StyleSheet } from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useAppDispatch, useAppSelector } from '@store';
import { toggleCampaignFavorite, toggleContactFavorite } from '@store/slices/favoritesSlice';
import { getColors } from '@theme/colors';

interface FavoriteButtonProps {
  id: string;
  type: 'campaign' | 'contact';
  size?: number;
  onPress?: () => void;
}

export const FavoriteButton: React.FC<FavoriteButtonProps> = ({
  id,
  type,
  size = 24,
  onPress,
}) => {
  const dispatch = useAppDispatch();
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  const isFavorite =
    type === 'campaign'
      ? useAppSelector((state) => state.favorites.campaignIds.includes(id))
      : useAppSelector((state) => state.favorites.contactIds.includes(id));

  const handlePress = () => {
    if (type === 'campaign') {
      dispatch(toggleCampaignFavorite(id));
    } else {
      dispatch(toggleContactFavorite(id));
    }
    onPress?.();
  };

  return (
    <TouchableOpacity
      onPress={handlePress}
      style={styles.button}
      activeOpacity={0.7}
    >
      <MaterialCommunityIcons
        name={isFavorite ? 'star' : 'star-outline'}
        size={size}
        color={isFavorite ? colors.warning : colors.textTertiary}
      />
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
  button: {
    padding: 8,
  },
});
