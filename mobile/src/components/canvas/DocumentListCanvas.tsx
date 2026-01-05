import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  RefreshControl,
} from 'react-native';
import { FileText, FileImage, FileSpreadsheet, File, ChevronRight, AlertCircle } from 'lucide-react-native';
import { useAppSelector } from '@store';
import { getColors } from '@theme/colors';
import { useCanvas, CanvasData } from '../../contexts/CanvasContext';
import * as documentService from '@services/documents';
import { formatRelativeTime } from '@utils/formatters';

interface Props {
  data: CanvasData;
  isSearchResults?: boolean;
}

export default function DocumentListCanvas({ data, isSearchResults = false }: Props) {
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);
  const { loadCanvas } = useCanvas();

  const [documents, setDocuments] = useState<documentService.Document[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadDocuments();
  }, [data.query]);

  const loadDocuments = async () => {
    try {
      setIsLoading(true);
      setError(null);

      if (isSearchResults && data.results) {
        // Use pre-provided search results
        setDocuments(data.results as documentService.Document[]);
      } else {
        // Fetch from API
        const result = await documentService.getDocuments({
          search: data.query,
          perPage: 50,
        });
        setDocuments(result.documents);
      }
    } catch (err: any) {
      setError(err.message || 'Failed to load documents');
    } finally {
      setIsLoading(false);
    }
  };

  const handleRefresh = async () => {
    setIsRefreshing(true);
    await loadDocuments();
    setIsRefreshing(false);
  };

  const handleDocumentPress = (doc: documentService.Document) => {
    loadCanvas('document_viewer', {
      asset_id: doc.id,
      document_id: doc.id,
      title: doc.original_filename,
    }, doc.original_filename);
  };

  const renderDocument = ({ item }: { item: documentService.Document }) => {
    const statusColor =
      item.processing_status === 'completed'
        ? colors.success
        : item.processing_status === 'processing'
        ? colors.warning
        : colors.error;

    return (
      <TouchableOpacity
        style={[styles.documentItem, { backgroundColor: colors.surface, borderColor: colors.border }]}
        onPress={() => handleDocumentPress(item)}
        activeOpacity={0.7}
      >
        <View style={[styles.iconContainer, { backgroundColor: colors.primaryLight }]}>
          {(() => {
            const iconName = documentService.getFileIcon(item.content_type);
            const IconComponent = iconName.includes('image') ? FileImage
              : iconName.includes('spreadsheet') || iconName.includes('table') ? FileSpreadsheet
              : iconName.includes('file-document') || iconName.includes('pdf') ? FileText
              : File;
            return <IconComponent size={28} color={colors.primary} />;
          })()}
        </View>

        <View style={styles.documentInfo}>
          <Text style={[styles.documentName, { color: colors.text }]} numberOfLines={1}>
            {item.original_filename}
          </Text>
          <View style={styles.documentMeta}>
            <Text style={[styles.documentSize, { color: colors.textTertiary }]}>
              {documentService.formatFileSize(item.file_size_bytes)}
            </Text>
            <Text style={[styles.documentDate, { color: colors.textTertiary }]}>
              {formatRelativeTime(item.created_at)}
            </Text>
          </View>
        </View>

        <View style={styles.statusContainer}>
          {item.processing_status === 'processing' ? (
            <ActivityIndicator size="small" color={colors.warning} />
          ) : (
            <View style={[styles.statusDot, { backgroundColor: statusColor }]} />
          )}
        </View>

        <ChevronRight size={24} color={colors.textTertiary} />
      </TouchableOpacity>
    );
  };

  const renderEmpty = () => (
    <View style={styles.emptyContainer}>
      <FileText size={64} color={colors.textTertiary} />
      <Text style={[styles.emptyTitle, { color: colors.textSecondary }]}>
        {isSearchResults ? 'No results found' : 'No documents yet'}
      </Text>
      <Text style={[styles.emptySubtitle, { color: colors.textTertiary }]}>
        {isSearchResults
          ? 'Try a different search term'
          : 'Upload documents to get started'}
      </Text>
    </View>
  );

  if (isLoading && documents.length === 0) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
        <Text style={[styles.loadingText, { color: colors.textSecondary }]}>
          Loading documents...
        </Text>
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.errorContainer}>
        <AlertCircle size={48} color={colors.error} />
        <Text style={[styles.errorText, { color: colors.error }]}>{error}</Text>
        <TouchableOpacity
          style={[styles.retryButton, { backgroundColor: colors.primary }]}
          onPress={loadDocuments}
        >
          <Text style={styles.retryButtonText}>Retry</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {/* Header info */}
      <View style={[styles.header, { borderBottomColor: colors.border }]}>
        <Text style={[styles.headerText, { color: colors.textSecondary }]}>
          {documents.length} document{documents.length !== 1 ? 's' : ''}
          {isSearchResults && data.query ? ` matching "${data.query}"` : ''}
        </Text>
      </View>

      <FlatList
        data={documents}
        renderItem={renderDocument}
        keyExtractor={(item) => item.id}
        ListEmptyComponent={renderEmpty}
        contentContainerStyle={styles.listContent}
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={handleRefresh}
            tintColor={colors.primary}
          />
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
  },
  headerText: {
    fontSize: 13,
  },
  listContent: {
    flexGrow: 1,
    padding: 16,
  },
  documentItem: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 12,
    borderRadius: 12,
    borderWidth: 1,
    marginBottom: 10,
  },
  iconContainer: {
    width: 48,
    height: 48,
    borderRadius: 10,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  documentInfo: {
    flex: 1,
    marginRight: 8,
  },
  documentName: {
    fontSize: 15,
    fontWeight: '500',
    marginBottom: 4,
  },
  documentMeta: {
    flexDirection: 'row',
    gap: 8,
  },
  documentSize: {
    fontSize: 12,
  },
  documentDate: {
    fontSize: 12,
  },
  statusContainer: {
    marginRight: 8,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingText: {
    marginTop: 12,
    fontSize: 14,
  },
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  errorText: {
    fontSize: 14,
    marginTop: 12,
    textAlign: 'center',
  },
  retryButton: {
    marginTop: 16,
    paddingHorizontal: 24,
    paddingVertical: 10,
    borderRadius: 8,
  },
  retryButtonText: {
    color: '#fff',
    fontWeight: '600',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 60,
  },
  emptyTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginTop: 16,
  },
  emptySubtitle: {
    fontSize: 14,
    marginTop: 8,
    textAlign: 'center',
  },
});
