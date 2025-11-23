import React from 'react';
import {
  View,
  StyleSheet,
  TouchableOpacity,
  Animated,
  ViewStyle,
} from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useAppSelector } from '@store';
import { getColors } from '@theme/colors';

interface SwipeableListItemProps {
  onDelete?: () => void;
  onEdit?: () => void;
  onArchive?: () => void;
  children: React.ReactNode;
  style?: ViewStyle;
  canDelete?: boolean;
  canEdit?: boolean;
  canArchive?: boolean;
}

export const SwipeableListItem: React.FC<SwipeableListItemProps> = ({
  onDelete,
  onEdit,
  onArchive,
  children,
  style,
  canDelete = true,
  canEdit = true,
  canArchive = true,
}) => {
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  const [isOpen, setIsOpen] = React.useState(false);
  const animatedValue = React.useRef(new Animated.Value(0)).current;

  const actionCount = [canEdit, canArchive, canDelete].filter(Boolean).length;
  const actionWidth = 60;
  const totalWidth = actionCount * actionWidth;

  const handleOpen = () => {
    setIsOpen(true);
    Animated.timing(animatedValue, {
      toValue: -totalWidth,
      duration: 300,
      useNativeDriver: false,
    }).start();
  };

  const handleClose = () => {
    setIsOpen(false);
    Animated.timing(animatedValue, {
      toValue: 0,
      duration: 300,
      useNativeDriver: false,
    }).start();
  };

  const handleDelete = () => {
    handleClose();
    onDelete?.();
  };

  const handleEdit = () => {
    handleClose();
    onEdit?.();
  };

  const handleArchive = () => {
    handleClose();
    onArchive?.();
  };

  return (
    <View style={[styles.container, style]}>
      {/* Action buttons */}
      <View
        style={[
          styles.actionsContainer,
          {
            width: totalWidth,
            backgroundColor: colors.surface,
          },
        ]}
      >
        {canEdit && (
          <TouchableOpacity
            style={[styles.actionButton, { backgroundColor: colors.info }]}
            onPress={handleEdit}
          >
            <MaterialCommunityIcons name="pencil" size={20} color="#fff" />
          </TouchableOpacity>
        )}

        {canArchive && (
          <TouchableOpacity
            style={[styles.actionButton, { backgroundColor: colors.warning }]}
            onPress={handleArchive}
          >
            <MaterialCommunityIcons name="archive" size={20} color="#fff" />
          </TouchableOpacity>
        )}

        {canDelete && (
          <TouchableOpacity
            style={[styles.actionButton, { backgroundColor: colors.error }]}
            onPress={handleDelete}
          >
            <MaterialCommunityIcons name="delete" size={20} color="#fff" />
          </TouchableOpacity>
        )}
      </View>

      {/* Content */}
      <Animated.View
        style={[
          styles.contentContainer,
          {
            transform: [{ translateX: animatedValue }],
            backgroundColor: colors.background,
          },
        ]}
      >
        <TouchableOpacity
          activeOpacity={1}
          onPress={isOpen ? handleClose : undefined}
        >
          {children}
        </TouchableOpacity>

        {!isOpen && (
          <TouchableOpacity
            style={styles.swipeHint}
            onLongPress={handleOpen}
          >
            <MaterialCommunityIcons
              name="chevron-left"
              size={20}
              color={colors.textTertiary}
            />
          </TouchableOpacity>
        )}
      </Animated.View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    overflow: 'hidden',
    borderRadius: 8,
  },
  actionsContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  actionButton: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 16,
  },
  contentContainer: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  swipeHint: {
    paddingHorizontal: 8,
    paddingVertical: 16,
  },
});
