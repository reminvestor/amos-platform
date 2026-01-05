import { apiClient } from './api';

export interface VoiceSessionResponse {
  id: string;
  status: 'active' | 'inactive';
  token?: string;
  expiresAt?: number;
}

export interface VoiceMetrics {
  providersStatus: Record<string, any>;
  sessionMetrics: Record<string, any>;
  healthScore: number;
}

/**
 * Create voice session for real-time transcription
 */
export async function createVoiceSession(): Promise<VoiceSessionResponse> {
  try {
    const response = await apiClient.post<VoiceSessionResponse>(
      '/api/voice/sessions',
      {}
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to create voice session',
      status: error.response?.status,
    };
  }
}

/**
 * Get voice session details
 */
export async function getVoiceSession(sessionId: string): Promise<VoiceSessionResponse> {
  try {
    const response = await apiClient.get<VoiceSessionResponse>(
      `/api/voice/sessions/${sessionId}`
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch voice session',
      status: error.response?.status,
    };
  }
}

/**
 * End voice session
 */
export async function endVoiceSession(sessionId: string): Promise<void> {
  try {
    await apiClient.patch(`/api/voice/sessions/${sessionId}/end`, {});
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to end voice session',
      status: error.response?.status,
    };
  }
}

/**
 * Synthesize text to speech
 */
export async function synthesizeToSpeech(data: {
  text: string;
  voice?: string;
  speed?: number;
}): Promise<{ audioUrl: string; duration: number }> {
  try {
    const response = await apiClient.post<{ audioUrl: string; duration: number }>(
      '/api/tts/synthesize',
      data
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to synthesize speech',
      status: error.response?.status,
    };
  }
}

/**
 * Get available TTS voices
 */
export async function getTTSVoices(): Promise<Array<{ id: string; name: string; language: string }>> {
  try {
    const response = await apiClient.get<Array<{ id: string; name: string; language: string }>>(
      '/api/tts/voices'
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch voices',
      status: error.response?.status,
    };
  }
}

/**
 * Get TTS preferences
 */
export async function getTTSPreferences(): Promise<{
  selectedVoice: string;
  speed: number;
  enabled: boolean;
}> {
  try {
    const response = await apiClient.get<{
      selectedVoice: string;
      speed: number;
      enabled: boolean;
    }>('/api/tts/preferences');
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch preferences',
      status: error.response?.status,
    };
  }
}

/**
 * Update TTS preferences
 */
export async function updateTTSPreferences(data: {
  selectedVoice?: string;
  speed?: number;
  enabled?: boolean;
}): Promise<void> {
  try {
    await apiClient.patch('/api/tts/preferences', data);
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to update preferences',
      status: error.response?.status,
    };
  }
}

/**
 * Get voice health status
 */
export async function getVoiceHealth(): Promise<{
  status: string;
  providers: Record<string, any>;
  metrics: VoiceMetrics;
}> {
  try {
    const response = await apiClient.get<{
      status: string;
      providers: Record<string, any>;
      metrics: VoiceMetrics;
    }>('/api/voice/health/status');
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch health status',
      status: error.response?.status,
    };
  }
}

/**
 * Pre-warm voice connections
 */
export async function prewarmVoiceConnections(): Promise<{ success: boolean }> {
  try {
    const response = await apiClient.post<{ success: boolean }>(
      '/api/voice/health/prewarm',
      {}
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to prewarm connections',
      status: error.response?.status,
    };
  }
}
