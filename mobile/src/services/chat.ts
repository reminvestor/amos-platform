import { apiClient } from './api';
import { ChatMessage } from '@types';

/**
 * Send chat message and get streaming response
 */
export async function* sendChatMessage(message: string, contextId?: string): AsyncGenerator<string> {
  try {
    // Create an event source for SSE streaming
    const response = await fetch('/scout/chat_stream', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${await getToken()}`,
      },
      body: JSON.stringify({
        message,
        context: contextId,
      }),
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    const reader = response.body?.getReader();
    if (!reader) {
      throw new Error('Response body is empty');
    }

    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');

      // Keep the last incomplete line in the buffer
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (line.startsWith('data: ')) {
          try {
            const data = JSON.parse(line.slice(6));
            if (data.text) {
              yield data.text;
            }
          } catch (e) {
            console.error('Failed to parse SSE data:', e);
          }
        }
      }
    }

    // Handle remaining buffer
    if (buffer.startsWith('data: ')) {
      try {
        const data = JSON.parse(buffer.slice(6));
        if (data.text) {
          yield data.text;
        }
      } catch (e) {
        console.error('Failed to parse final SSE data:', e);
      }
    }
  } catch (error: any) {
    throw {
      message: error.message || 'Failed to send message',
      status: error.status,
      details: error,
    };
  }
}

/**
 * Get chat history with pagination
 */
export async function getChatHistory(params: {
  page?: number;
  perPage?: number;
}): Promise<ChatMessage[]> {
  try {
    const queryParams = new URLSearchParams();
    if (params.page) queryParams.append('page', params.page.toString());
    if (params.perPage) queryParams.append('per_page', params.perPage.toString());

    const response = await apiClient.get<ChatMessage[]>(
      `/scout/history?${queryParams.toString()}`
    );
    return response;
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
export async function clearConversation(): Promise<void> {
  try {
    await apiClient.delete('/scout/conversation');
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

/**
 * Get stored token
 */
async function getToken(): Promise<string | null> {
  // This will be imported from storage in actual implementation
  return null;
}
