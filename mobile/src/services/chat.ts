import { apiClient } from './api';
import { ChatMessage } from '@types';
import { Config } from '@config';
import * as storage from '@utils/storage';
import { Platform } from 'react-native';

/**
 * Send chat message and get streaming response
 * Note: React Native doesn't support ReadableStream, so we use text() and parse SSE events
 */
export async function* sendChatMessage(message: string, contextId?: string): AsyncGenerator<string> {
  try {
    const token = await storage.getToken();

    // For React Native, we need to use XMLHttpRequest for streaming support
    // or fall back to non-streaming response
    const response = await fetch(`${Config.api.baseURL}/scout/chat_stream`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
        'Accept': 'text/event-stream',
      },
      body: JSON.stringify({
        message,
        context: contextId,
      }),
      // Enable react-native-fetch-api streaming (if available)
      // @ts-ignore - React Native specific option
      reactNative: { textStreaming: true },
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`HTTP ${response.status}: ${errorText || response.statusText}`);
    }

    // Try streaming approach first (works in newer Expo/RN versions)
    if (response.body && typeof response.body.getReader === 'function') {
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          const content = parseSSELine(line);
          if (content) yield content;
        }
      }

      // Handle remaining buffer
      if (buffer) {
        const content = parseSSELine(buffer);
        if (content) yield content;
      }
    } else {
      // Fallback: Parse full response text as SSE
      // React Native may not support streaming, so we get the full response
      const text = await response.text();
      const lines = text.split('\n');

      for (const line of lines) {
        const content = parseSSELine(line);
        if (content) yield content;
      }
    }
  } catch (error: any) {
    console.error('Chat error:', error);
    throw {
      message: error.message || 'Failed to send message',
      status: error.status,
      details: error,
    };
  }
}

/**
 * SSE event data structure
 */
export interface SSEEvent {
  type: 'content' | 'task_progress' | 'task_completed' | 'task_failed' | 'load_canvas' | 'transient' | 'user_input_required' | 'update';
  text?: string;
  message?: string;
  task_id?: string;
  status?: string;
  progress?: number;
  agent_type?: string;
  started_at?: string;
  error?: string;
  canvas_type?: string;
  canvas_data?: any;
  [key: string]: any;
}

/**
 * Callback type for handling SSE events
 */
export type SSEEventCallback = (event: SSEEvent) => void;

// Global event callback that can be set from ChatScreen
let globalEventCallback: SSEEventCallback | null = null;

export function setSSEEventCallback(callback: SSEEventCallback | null) {
  globalEventCallback = callback;
}

/**
 * Parse a single SSE line and extract content
 */
function parseSSELine(line: string): string | null {
  if (!line.startsWith('data: ')) return null;

  try {
    const data = JSON.parse(line.slice(6)) as SSEEvent;

    // Emit the raw event to callback if set
    if (globalEventCallback) {
      globalEventCallback(data);
    }

    // Handle different SSE response formats:
    // - Server sends: {"type":"update","message":"..."} for streaming content
    // - Server may also send: {"type":"content","text":"..."} for final content
    // Skip task/canvas events from text content (they're handled by callback)
    const isTaskEvent = data.type === 'task_progress' || data.type === 'task_completed' || data.type === 'task_failed';
    const isCanvasEvent = data.type === 'load_canvas';

    const content = data.text || data.message;
    if (content && data.type !== 'transient' && !isTaskEvent && !isCanvasEvent) {
      return content;
    }
  } catch (e) {
    // Ignore parse errors for non-JSON data lines
  }
  return null;
}

/**
 * Get chat history with pagination
 */
export async function getChatHistory(params: {
  page?: number;
  perPage?: number;
  beforeId?: string;
}): Promise<{ messages: ChatMessage[]; hasMore: boolean; total: number }> {
  try {
    const queryParams = new URLSearchParams();
    if (params.perPage) queryParams.append('limit', params.perPage.toString());
    if (params.beforeId) queryParams.append('before_id', params.beforeId);

    const response = await apiClient.get<{ messages: ChatMessage[]; has_more: boolean; total: number }>(
      `/api/v1/chat/history?${queryParams.toString()}`
    );
    return {
      messages: response.messages || [],
      hasMore: response.has_more || false,
      total: response.total || 0
    };
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch chat history',
      status: error.response?.status,
    };
  }
}

/**
 * Clear conversation history
 */
export async function clearConversation(sessionId?: string): Promise<void> {
  try {
    const queryParams = sessionId ? `?session_id=${sessionId}` : '';
    await apiClient.delete(`/api/v1/chat/clear${queryParams}`);
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to clear conversation',
      status: error.response?.status,
    };
  }
}

/**
 * Save chat context for later reference
 */
export async function saveChatContext(data: {
  title: string;
  messages: ChatMessage[];
}): Promise<{ id: string }> {
  try {
    const response = await apiClient.post<{ id: string }>(
      '/scout/save_context',
      data
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to save context',
      status: error.response?.status,
    };
  }
}

