import React from 'react';
import {
  View,
  Modal,
  StyleSheet,
  TouchableOpacity,
  Keyboard,
  Platform,
  SafeAreaView,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useAppSelector } from '@store';
import { getColors } from '@theme/colors';
import { StyledText } from './StyledText';

interface BottomSheetProps {
  visible: boolean;
  onClose: () => void;
  title?: string;
  children: React.ReactNode;
}

export const BottomSheet: React.FC<BottomSheetProps> = ({ visible, onClose, title, children }) => {
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);
  const insets = useSafeAreaInsets();

  const handleBackdropPress = () => {
    Keyboard.dismiss();
    onClose();
  };

  return (
    <Modal
      visible={visible}
      transparent
      animationType="slide"
      onRequestClose={onClose}
    >
      <TouchableOpacity
        style={[styles.backdrop, { backgroundColor: colors.overlay }]}
        activeOpacity={1}
        onPress={handleBackdropPress}
      >
        <TouchableOpacity activeOpacity={1} onPress={(e) => e.stopPropagation()}>
          <SafeAreaView
            style={[
              styles.content,
              {
                backgroundColor: colors.surface,
                marginBottom: Platform.OS === 'android' ? insets.bottom : 0,
              },
            ]}
          >
            {title && (
              <View style={[styles.header, { borderBottomColor: colors.border }]}>
                <StyledText style={[styles.title, { color: colors.text }]}>{title}</StyledText>
                <TouchableOpacity onPress={onClose} style={styles.closeButton}>
                  <StyledText style={{ color: colors.primary, fontSize: 18 }}>✕</StyledText>
                </TouchableOpacity>
              </View>
            )}
            <View style={styles.body}>{children}</View>
          </SafeAreaView>
        </TouchableOpacity>
      </TouchableOpacity>
    </Modal>
  );
};

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    justifyContent: 'flex-end',
  },
  content: {
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    maxHeight: '80%',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
  },
  title: {
    fontSize: 18,
    fontWeight: '600',
  },
  closeButton: {
    padding: 8,
  },
  body: {
    paddingHorizontal: 16,
    paddingVertical: 16,
  },
});
