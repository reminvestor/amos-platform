import { apiClient } from './api';
import { Config } from '@config';
import * as storage from '@utils/storage';

export interface Document {
  id: string;
  original_filename: string;
  content_type: string;
  file_size_bytes: number;
  processing_status: 'processing' | 'completed' | 'failed';
  created_at: string;
  updated_at: string;
  file_url?: string;
  thumbnail_url?: string;
}

export interface UploadedFile {
  url: string;
  filename: string;
  content_type: string;
  size: number;
  asset_id?: string;
  asset_type: 'document' | 'image' | 'temporary';
  processing?: boolean;
}

export interface UploadResult {
  success: boolean;
  urls: UploadedFile[];
  error?: string;
}

/**
 * Upload files to server for RAG storage
 * @param files - Array of file objects with uri, name, type
 * @param storageType - 'long-term' for RAG storage, 'short-term' for temporary
 */
export async function uploadFiles(
  files: Array<{ uri: string; name: string; type: string }>,
  storageType: 'long-term' | 'short-term' = 'long-term'
): Promise<UploadResult> {
  try {
    const token = await storage.getToken();
    const formData = new FormData();

    files.forEach((file, index) => {
      // React Native requires this specific format for FormData files
      formData.append(`files[${index}]`, {
        uri: file.uri,
        name: file.name,
        type: file.type,
      } as any);
    });

    formData.append('storage_type', storageType);

    const response = await fetch(`${Config.api.baseURL}/scout/upload_files`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        // Let fetch set Content-Type with boundary for FormData
      },
      body: formData,
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new Error(errorData.message || `Upload failed: ${response.status}`);
    }

    const data = await response.json();
    return {
      success: true,
      urls: data.urls || [],
    };
  } catch (error: any) {
    console.error('Upload error:', error);
    return {
      success: false,
      urls: [],
      error: error.message || 'Failed to upload files',
    };
  }
}

/**
 * Get list of documents from RAG storage
 */
export async function getDocuments(params?: {
  page?: number;
  perPage?: number;
  search?: string;
}): Promise<{ documents: Document[]; total: number; hasMore: boolean }> {
  try {
    const queryParams = new URLSearchParams();
    if (params?.page) queryParams.append('page', params.page.toString());
    if (params?.perPage) queryParams.append('per_page', params.perPage.toString());
    if (params?.search) queryParams.append('search', params.search);

    const response = await apiClient.get<any>(
      `/api/v1/documents?${queryParams.toString()}`
    );

    return {
      documents: response.data || response.documents || [],
      total: response.pagination?.total_count || response.total || 0,
      hasMore: response.pagination?.has_more || false,
    };
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch documents',
      status: error.response?.status,
    };
  }
}

/**
 * Get single document details
 */
export async function getDocument(id: string): Promise<Document> {
  try {
    const response = await apiClient.get<Document>(`/api/v1/documents/${id}`);
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch document',
      status: error.response?.status,
    };
  }
}

/**
 * Delete a document
 */
export async function deleteDocument(id: string): Promise<void> {
  try {
    await apiClient.delete(`/api/v1/documents/${id}`);
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to delete document',
      status: error.response?.status,
    };
  }
}

/**
 * Search documents using RAG semantic search
 */
export async function searchDocuments(query: string): Promise<{
  results: Array<{
    document_id: string;
    filename: string;
    snippet: string;
    score: number;
  }>;
}> {
  try {
    const response = await apiClient.post<any>('/api/v1/documents/search', {
      query,
    });
    return {
      results: response.results || [],
    };
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to search documents',
      status: error.response?.status,
    };
  }
}

/**
 * Get file icon name based on content type
 */
export function getFileIcon(contentType: string): string {
  if (contentType.includes('pdf')) return 'file-pdf-box';
  if (contentType.includes('word') || contentType.includes('document')) return 'file-word-box';
  if (contentType.includes('excel') || contentType.includes('spreadsheet')) return 'file-excel-box';
  if (contentType.includes('powerpoint') || contentType.includes('presentation')) return 'file-powerpoint-box';
  if (contentType.includes('image')) return 'file-image';
  if (contentType.includes('text')) return 'file-document-outline';
  return 'file-outline';
}

/**
 * Format file size for display
 */
export function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
