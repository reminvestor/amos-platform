import React from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  Modal,
  Animated,
  Dimensions,
} from 'react-native';
import { X, LayoutDashboard } from 'lucide-react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useCanvas } from '../../contexts/CanvasContext';
import { useAppSelector } from '@store';
import { getColors } from '@theme/colors';

// Import canvas components
import DocumentListCanvas from './DocumentListCanvas';
import DocumentViewerCanvas from './DocumentViewerCanvas';

const { height: SCREEN_HEIGHT } = Dimensions.get('window');

export default function CanvasContainer() {
  const { canvas, closeCanvas, isCanvasVisible } = useCanvas();
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);
  const insets = useSafeAreaInsets();

  const renderCanvasContent = () => {
    switch (canvas.type) {
      case 'document_list':
        return <DocumentListCanvas data={canvas.data} />;
      case 'document_viewer':
        return <DocumentViewerCanvas data={canvas.data} />;
      case 'document_search_results':
        return <DocumentListCanvas data={canvas.data} isSearchResults />;
      // Add more canvas types as needed
      case 'landing_page_viewer':
      case 'campaign_viewer':
      case 'contact_viewer':
      case 'analytics_dashboard':
      case 'task_progress':
      case 'integrations_manager':
        return (
          <View style={styles.placeholder}>
            <LayoutDashboard size={48} color={colors.textTertiary} />
            <Text style={[styles.placeholderText, { color: colors.textSecondary }]}>
              {canvas.title} canvas
            </Text>
            <Text style={[styles.placeholderSubtext, { color: colors.textTertiary }]}>
              Coming soon
            </Text>
          </View>
        );
      default:
        return null;
    }
  };

  if (!isCanvasVisible || !canvas.type) {
    return null;
  }

  return (
    <Modal
      visible={isCanvasVisible}
      animationType="slide"
      presentationStyle="pageSheet"
      onRequestClose={closeCanvas}
    >
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        {/* Header */}
        <View
          style={[
            styles.header,
            {
              backgroundColor: colors.surface,
              borderBottomColor: colors.border,
              paddingTop: insets.top || 16,
            },
          ]}
        >
          <View style={styles.headerLeft}>
            <TouchableOpacity onPress={closeCanvas} style={styles.closeButton}>
              <X size={24} color={colors.text} />
            </TouchableOpacity>
          </View>
          <Text style={[styles.headerTitle, { color: colors.text }]}>
            {canvas.title}
          </Text>
          <View style={styles.headerRight} />
        </View>

        {/* Canvas Content */}
        <View style={styles.content}>
          {renderCanvasContent()}
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingBottom: 12,
    borderBottomWidth: 1,
  },
  headerLeft: {
    width: 44,
  },
  headerRight: {
    width: 44,
  },
  closeButton: {
    padding: 4,
  },
  headerTitle: {
    fontSize: 17,
    fontWeight: '600',
    flex: 1,
    textAlign: 'center',
  },
  content: {
    flex: 1,
  },
  placeholder: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  placeholderText: {
    fontSize: 16,
    fontWeight: '500',
    marginTop: 16,
  },
  placeholderSubtext: {
    fontSize: 14,
    marginTop: 8,
  },
});
