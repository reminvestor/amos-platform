import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, Image } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { MessageSquarePlus } from 'lucide-react-native';
import { useNavigation } from '@react-navigation/native';
import { useAppSelector } from '@store';
import { getColors } from '@theme/colors';

// Import logo asset
const logoHeader = require('../../assets/logo-header.png');

interface AppHeaderProps {
  title?: string;
  subtitle?: string;
  showNewChat?: boolean;
}

export default function AppHeader({ title = 'Amos Labs', subtitle, showNewChat = true }: AppHeaderProps) {
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);
  const navigation = useNavigation<any>();
  const insets = useSafeAreaInsets();

  const handleNewConversation = () => {
    // Navigate to AMOS tab and signal to start a new conversation
    navigation.navigate('AMOS', { resetChat: Date.now() });
  };

  return (
    <View style={[
      styles.header,
      {
        borderBottomColor: colors.border,
        backgroundColor: colors.background,
        paddingTop: insets.top + 8,
      }
    ]}>
      <View style={styles.headerTitleContainer}>
        <Image
          source={logoHeader}
          style={[
            styles.logo,
            // Tint the white logo to match theme in light mode
            theme === 'light' && { tintColor: '#1a1a2e' }
          ]}
          resizeMode="contain"
        />
        {subtitle && (
          <>
            <Text style={[styles.headerSeparator, { color: colors.textTertiary }]}>|</Text>
            <Text style={[styles.headerSubtitle, { color: colors.textSecondary }]}>{subtitle}</Text>
          </>
        )}
      </View>
      {showNewChat && (
        <TouchableOpacity onPress={handleNewConversation} style={styles.headerButton}>
          <MessageSquarePlus
            size={24}
            color={colors.textSecondary}
          />
        </TouchableOpacity>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  header: {
    paddingHorizontal: 16,
    paddingBottom: 12,
    borderBottomWidth: 1,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  headerTitleContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  logo: {
    width: 100,
    height: 28,
  },
  headerSeparator: {
    fontSize: 16,
    marginHorizontal: 8,
  },
  headerSubtitle: {
    fontSize: 14,
  },
  headerButton: {
    padding: 4,
  },
});
