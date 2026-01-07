import { useState, useCallback, useRef, useEffect } from 'react';
import { Platform, Alert } from 'react-native';
import { Audio, InterruptionModeIOS, InterruptionModeAndroid } from 'expo-av';
import * as storage from '@utils/storage';
import { Config } from '@config';

interface VoiceInputState {
  isListening: boolean;
  isConnecting: boolean;
  transcript: string;
  partialTranscript: string;
  error: string | null;
}

interface ElevenLabsCredentials {
  api_key: string;
  model_id: string;
  websocket_url: string;
  config: {
    language_code: string;
    sample_rate: number;
    encoding: string;
  };
}

export function useVoiceInput(onTranscriptComplete?: (text: string) => void) {
  const [state, setState] = useState<VoiceInputState>({
    isListening: false,
    isConnecting: false,
    transcript: '',
    partialTranscript: '',
    error: null,
  });

  const recordingRef = useRef<Audio.Recording | null>(null);
  const websocketRef = useRef<WebSocket | null>(null);
  const sessionIdRef = useRef<string | null>(null);
  const transcriptBufferRef = useRef<string>('');
  const silenceTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      stopListening();
    };
  }, []);

  const requestMicrophonePermission = async (): Promise<boolean> => {
    try {
      const { status } = await Audio.requestPermissionsAsync();
      if (status !== 'granted') {
        Alert.alert(
          'Microphone Permission Required',
          'Please enable microphone access in your device settings to use voice input.'
        );
        return false;
      }
      return true;
    } catch (error) {
      console.error('Error requesting microphone permission:', error);
      return false;
    }
  };

  const createVoiceSession = async (): Promise<string> => {
    const token = await storage.getToken();
    const response = await fetch(`${Config.api.baseURL}/api/voice/sessions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
    });

    if (!response.ok) {
      throw new Error('Failed to create voice session');
    }

    const data = await response.json();
    return data.session_id;
  };

  const getElevenLabsCredentials = async (sessionId: string): Promise<ElevenLabsCredentials> => {
    const token = await storage.getToken();
    const response = await fetch(
      `${Config.api.baseURL}/api/voice/sessions/${sessionId}/eleven_labs_credentials`,
      {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      }
    );

    if (!response.ok) {
      throw new Error('Failed to get Eleven Labs credentials');
    }

    return response.json();
  };

  const connectWebSocket = async (credentials: ElevenLabsCredentials): Promise<WebSocket> => {
    return new Promise((resolve, reject) => {
      // Build WebSocket URL with parameters
      const wsUrl = new URL(credentials.websocket_url);
      wsUrl.searchParams.set('model_id', credentials.model_id || 'scribe_v1');
      wsUrl.searchParams.set('language_code', credentials.config?.language_code || 'en');

      const ws = new WebSocket(wsUrl.toString());

      const timeout = setTimeout(() => {
        ws.close();
        reject(new Error('WebSocket connection timeout'));
      }, 10000);

      ws.onopen = () => {
        clearTimeout(timeout);
        console.log('Eleven Labs WebSocket connected');

        // Send initial configuration with API key
        const initMessage = {
          type: 'init',
          api_key: credentials.api_key,
          sample_rate: credentials.config?.sample_rate || 16000,
          encoding: credentials.config?.encoding || 'pcm_s16le',
        };
        ws.send(JSON.stringify(initMessage));

        resolve(ws);
      };

      ws.onerror = (error) => {
        clearTimeout(timeout);
        console.error('WebSocket error:', error);
        reject(new Error('WebSocket connection failed'));
      };

      ws.onclose = () => {
        console.log('Eleven Labs WebSocket closed');
      };
    });
  };

  const handleWebSocketMessage = (event: MessageEvent) => {
    try {
      const data = JSON.parse(event.data);

      if (data.type === 'transcript') {
        const text = data.text || '';
        const isFinal = data.is_final || false;

        if (isFinal && text.trim()) {
          // Accumulate final transcripts
          transcriptBufferRef.current += (transcriptBufferRef.current ? ' ' : '') + text.trim();

          setState((prev) => ({
            ...prev,
            transcript: transcriptBufferRef.current,
            partialTranscript: '',
          }));

          // Reset silence timeout
          if (silenceTimeoutRef.current) {
            clearTimeout(silenceTimeoutRef.current);
          }

          // Auto-submit after 2 seconds of silence
          silenceTimeoutRef.current = setTimeout(() => {
            if (transcriptBufferRef.current.trim() && onTranscriptComplete) {
              onTranscriptComplete(transcriptBufferRef.current.trim());
              transcriptBufferRef.current = '';
              setState((prev) => ({ ...prev, transcript: '' }));
            }
          }, 2000);
        } else if (!isFinal) {
          setState((prev) => ({
            ...prev,
            partialTranscript: text,
          }));
        }
      } else if (data.type === 'error') {
        console.error('Eleven Labs error:', data.message);
        setState((prev) => ({ ...prev, error: data.message }));
      }
    } catch (error) {
      console.error('Error parsing WebSocket message:', error);
    }
  };

  const startRecording = async () => {
    try {
      await Audio.setAudioModeAsync({
        allowsRecordingIOS: true,
        playsInSilentModeIOS: true,
        interruptionModeIOS: InterruptionModeIOS.DoNotMix,
        interruptionModeAndroid: InterruptionModeAndroid.DoNotMix,
        shouldDuckAndroid: true,
        playThroughEarpieceAndroid: false,
      });

      const recording = new Audio.Recording();

      // Configure for PCM audio that Eleven Labs expects
      await recording.prepareToRecordAsync({
        android: {
          extension: '.wav',
          outputFormat: Audio.AndroidOutputFormat.DEFAULT,
          audioEncoder: Audio.AndroidAudioEncoder.DEFAULT,
          sampleRate: 16000,
          numberOfChannels: 1,
          bitRate: 256000,
        },
        ios: {
          extension: '.wav',
          outputFormat: Audio.IOSOutputFormat.LINEARPCM,
          audioQuality: Audio.IOSAudioQuality.HIGH,
          sampleRate: 16000,
          numberOfChannels: 1,
          bitRate: 256000,
          linearPCMBitDepth: 16,
          linearPCMIsBigEndian: false,
          linearPCMIsFloat: false,
        },
        web: {
          mimeType: 'audio/webm',
          bitsPerSecond: 256000,
        },
      });

      // Set up audio streaming callback
      recording.setOnRecordingStatusUpdate((status) => {
        if (status.isRecording && websocketRef.current?.readyState === WebSocket.OPEN) {
          // Note: expo-av doesn't support streaming audio chunks directly
          // We need to use a different approach for real-time streaming
        }
      });

      await recording.startAsync();
      recordingRef.current = recording;

      console.log('Recording started');
    } catch (error) {
      console.error('Error starting recording:', error);
      throw error;
    }
  };

  const stopRecording = async (): Promise<string | null> => {
    if (!recordingRef.current) return null;

    try {
      await recordingRef.current.stopAndUnloadAsync();
      const uri = recordingRef.current.getURI();
      recordingRef.current = null;

      await Audio.setAudioModeAsync({
        allowsRecordingIOS: false,
      });

      return uri;
    } catch (error) {
      console.error('Error stopping recording:', error);
      return null;
    }
  };

  const startListening = useCallback(async () => {
    if (state.isListening || state.isConnecting) return;

    setState((prev) => ({ ...prev, isConnecting: true, error: null }));

    try {
      // Request microphone permission
      const hasPermission = await requestMicrophonePermission();
      if (!hasPermission) {
        setState((prev) => ({ ...prev, isConnecting: false }));
        return;
      }

      // Create voice session
      console.log('Creating voice session...');
      const sessionId = await createVoiceSession();
      sessionIdRef.current = sessionId;
      console.log('Voice session created:', sessionId);

      // Get Eleven Labs credentials
      console.log('Getting Eleven Labs credentials...');
      const credentials = await getElevenLabsCredentials(sessionId);
      console.log('Got credentials');

      // Connect WebSocket
      console.log('Connecting to Eleven Labs...');
      const ws = await connectWebSocket(credentials);
      websocketRef.current = ws;

      ws.onmessage = handleWebSocketMessage;
      ws.onclose = () => {
        if (state.isListening) {
          stopListening();
        }
      };

      // Start recording
      await startRecording();

      setState((prev) => ({
        ...prev,
        isListening: true,
        isConnecting: false,
        transcript: '',
        partialTranscript: '',
      }));

      transcriptBufferRef.current = '';

      console.log('Voice input started successfully');
    } catch (error: any) {
      console.error('Error starting voice input:', error);
      setState((prev) => ({
        ...prev,
        isConnecting: false,
        error: error.message || 'Failed to start voice input',
      }));

      // Show user-friendly error
      Alert.alert(
        'Voice Input Error',
        'Could not start voice input. Please check your connection and try again.'
      );
    }
  }, [state.isListening, state.isConnecting]);

  const stopListening = useCallback(async () => {
    console.log('Stopping voice input...');

    // Clear silence timeout
    if (silenceTimeoutRef.current) {
      clearTimeout(silenceTimeoutRef.current);
      silenceTimeoutRef.current = null;
    }

    // Stop recording
    await stopRecording();

    // Close WebSocket
    if (websocketRef.current) {
      websocketRef.current.close();
      websocketRef.current = null;
    }

    // End voice session
    if (sessionIdRef.current) {
      try {
        const token = await storage.getToken();
        await fetch(
          `${Config.api.baseURL}/api/voice/sessions/${sessionIdRef.current}/end`,
          {
            method: 'PATCH',
            headers: {
              'Authorization': `Bearer ${token}`,
            },
          }
        );
      } catch (error) {
        console.error('Error ending voice session:', error);
      }
      sessionIdRef.current = null;
    }

    // Submit any remaining transcript
    const finalTranscript = transcriptBufferRef.current.trim();
    if (finalTranscript && onTranscriptComplete) {
      onTranscriptComplete(finalTranscript);
    }

    transcriptBufferRef.current = '';

    setState({
      isListening: false,
      isConnecting: false,
      transcript: '',
      partialTranscript: '',
      error: null,
    });

    console.log('Voice input stopped');
  }, [onTranscriptComplete]);

  const toggleListening = useCallback(async () => {
    if (state.isListening) {
      await stopListening();
    } else {
      await startListening();
    }
  }, [state.isListening, startListening, stopListening]);

  return {
    isListening: state.isListening,
    isConnecting: state.isConnecting,
    transcript: state.transcript,
    partialTranscript: state.partialTranscript,
    error: state.error,
    startListening,
    stopListening,
    toggleListening,
  };
}
