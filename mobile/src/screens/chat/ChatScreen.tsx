import React, { useState, useCallback, useEffect, useRef } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  FlatList,
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
  SafeAreaView,
  ActivityIndicator,
  Alert,
  Modal,
} from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useNavigation } from '@react-navigation/native';
import * as chatService from '@services/chat';
import { ChatMessage } from '@types';
import { formatRelativeTime } from '@utils/formatters';

export default function ChatScreen() {
  const navigation = useNavigation<any>();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [inputText, setInputText] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isListening, setIsListening] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showTaskMenu, setShowTaskMenu] = useState(false);
  const [selectedMessageForTask, setSelectedMessageForTask] = useState<ChatMessage | null>(null);
  const flatListRef = useRef<FlatList>(null);
  const inputRef = useRef<TextInput>(null);

  // Load chat history on mount
  useEffect(() => {
    loadChatHistory();
  }, []);

  // Scroll to bottom when new messages arrive
  useEffect(() => {
    if (messages.length > 0) {
      flatListRef.current?.scrollToEnd({ animated: true });
    }
  }, [messages]);

  const loadChatHistory = async () => {
    try {
      setIsLoading(true);
      const history = await chatService.getChatHistory({ page: 1, perPage: 50 });
      setMessages(
        history.map((msg) => ({
          ...msg,
          id: msg.id || `${Date.now()}-${Math.random()}`,
        }))
      );
      setError(null);
    } catch (err: any) {
      setError('Failed to load chat history');
      console.error('Error loading history:', err);
    } finally {
      setIsLoading(false);
    }
  };

  const handleSendMessage = async () => {
    if (!inputText.trim()) {
      return;
    }

    const userMessage: ChatMessage = {
      id: `${Date.now()}-user`,
      role: 'user',
      content: inputText,
      timestamp: new Date().toISOString(),
    };

    setMessages((prev) => [...prev, userMessage]);
    setInputText('');
    setError(null);

    try {
      setIsLoading(true);

      // Create AI message placeholder
      const aiMessageId = `${Date.now()}-ai`;
      const aiMessage: ChatMessage = {
        id: aiMessageId,
        role: 'assistant',
        content: '',
        timestamp: new Date().toISOString(),
        is_streaming: true,
      };

      setMessages((prev) => [...prev, aiMessage]);

      // Stream response
      let fullResponse = '';
      for await (const chunk of chatService.sendChatMessage(userMessage.content)) {
        fullResponse += chunk;

        // Update message with streaming content
        setMessages((prev) =>
          prev.map((msg) =>
            msg.id === aiMessageId
              ? { ...msg, content: fullResponse }
              : msg
          )
        );
      }

      // Mark as complete
      setMessages((prev) =>
        prev.map((msg) =>
          msg.id === aiMessageId
            ? { ...msg, is_streaming: false }
            : msg
        )
      );
    } catch (err: any) {
      setError(err.message || 'Failed to send message');
      // Remove incomplete AI message
      setMessages((prev) => prev.filter((msg) => msg.id !== `${Date.now()}-ai`));
    } finally {
      setIsLoading(false);
    }
  };

  const handleVoiceInput = async () => {
    // TODO: Implement STT with Eleven Labs Scribe v3 (matching web app implementation)
    // This will require WebSocket connection to Eleven Labs for real-time transcription
    // See: app/javascript/controllers/voice_assistant_controller.js for web implementation
    Alert.alert(
      'Voice Input Coming Soon',
      'STT (Speech-to-Text) using Eleven Labs Scribe v3 is planned to match the web app.'
    );
  };

  const handleClearChat = () => {
    Alert.alert(
      'Clear Conversation',
      'Are you sure you want to clear the chat history?',
      [
        { text: 'Cancel', onPress: () => {} },
        {
          text: 'Clear',
          onPress: async () => {
            try {
              await chatService.clearConversation();
              setMessages([]);
              setError(null);
            } catch (err: any) {
              setError('Failed to clear conversation');
            }
          },
          style: 'destructive',
        },
      ]
    );
  };

  const handleCreateTaskFromMessage = (message: ChatMessage) => {
    setSelectedMessageForTask(message);
    setShowTaskMenu(true);
  };

  const handleCreateQuickTask = () => {
    setShowTaskMenu(false);
    navigation.navigate('Tasks', {
      screen: 'TaskEdit',
      params: {
        mode: 'create',
        initialTitle: selectedMessageForTask?.content?.substring(0, 100) || '',
      },
    });
  };

  const renderMessage = ({ item }: { item: ChatMessage }) => {
    const isUser = item.role === 'user';

    return (
      <View
        style={[
          styles.messageContainer,
          isUser ? styles.userMessageContainer : styles.aiMessageContainer,
        ]}
      >
        <View
          style={[
            styles.messageBubble,
            isUser ? styles.userBubble : styles.aiBubble,
          ]}
        >
          <Text
            style={[
              styles.messageText,
              isUser ? styles.userText : styles.aiText,
            ]}
          >
            {item.content}
          </Text>
          {item.is_streaming && (
            <ActivityIndicator
              size="small"
              color={isUser ? '#fff' : '#333'}
              style={styles.streamingIndicator}
            />
          )}
        </View>
        <Text style={styles.timestamp}>
          {formatRelativeTime(item.timestamp)}
        </Text>
      </View>
    );
  };

  const renderEmpty = () => (
    <View style={styles.emptyContainer}>
      <MaterialCommunityIcons
        name="chat-outline"
        size={64}
        color="#ccc"
      />
      <Text style={styles.emptyTitle}>No messages yet</Text>
      <Text style={styles.emptySubtitle}>
        Start a conversation with the AI assistant
      </Text>
    </View>
  );

  return (
    <SafeAreaView style={styles.container}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.flex}
        keyboardVerticalOffset={90}
      >
        {/* Header with actions */}
        <View style={styles.header}>
          <Text style={styles.headerTitle}>Amos AI</Text>
          <View style={styles.headerActions}>
            <TouchableOpacity
              onPress={() => handleCreateTaskFromMessage(messages[messages.length - 1] || { id: '', role: 'user', content: '', timestamp: new Date().toISOString() })}
              disabled={messages.length === 0}
              style={styles.headerButton}
            >
              <MaterialCommunityIcons
                name="checkbox-marked-circle-plus-outline"
                size={24}
                color={messages.length > 0 ? '#666' : '#ccc'}
              />
            </TouchableOpacity>
            <TouchableOpacity
              onPress={handleClearChat}
              disabled={messages.length === 0}
              style={styles.headerButton}
            >
              <MaterialCommunityIcons
                name="delete-outline"
                size={24}
                color={messages.length > 0 ? '#666' : '#ccc'}
              />
            </TouchableOpacity>
          </View>
        </View>

        {/* Error message */}
        {error && (
          <View style={styles.errorBox}>
            <Text style={styles.errorText}>{error}</Text>
            <TouchableOpacity onPress={() => setError(null)}>
              <MaterialCommunityIcons name="close" size={20} color="#c33" />
            </TouchableOpacity>
          </View>
        )}

        {/* Messages list */}
        <FlatList
          ref={flatListRef}
          data={messages}
          renderItem={renderMessage}
          keyExtractor={(item) => item.id}
          ListEmptyComponent={renderEmpty}
          contentContainerStyle={styles.messagesList}
          scrollEnabled={messages.length > 0}
        />

        {/* Input area */}
        <View style={styles.inputContainer}>
          {isLoading ? (
            <View style={styles.loadingBox}>
              <ActivityIndicator size="small" color="#4A90E2" />
              <Text style={styles.loadingText}>AI is thinking...</Text>
            </View>
          ) : (
            <View style={styles.inputWrapper}>
              <TextInput
                ref={inputRef}
                style={styles.input}
                placeholder="Ask me anything..."
                placeholderTextColor="#999"
                value={inputText}
                onChangeText={setInputText}
                multiline
                maxLength={1000}
                editable={!isLoading}
              />

              <TouchableOpacity
                style={styles.voiceButton}
                onPress={handleVoiceInput}
                disabled={isLoading || isListening}
              >
                <MaterialCommunityIcons
                  name={isListening ? 'microphone' : 'microphone-outline'}
                  size={20}
                  color={isListening ? '#4A90E2' : '#666'}
                />
              </TouchableOpacity>

              <TouchableOpacity
                style={[
                  styles.sendButton,
                  (!inputText.trim() || isLoading) && styles.sendButtonDisabled,
                ]}
                onPress={handleSendMessage}
                disabled={!inputText.trim() || isLoading}
              >
                <MaterialCommunityIcons
                  name="send"
                  size={20}
                  color={
                    !inputText.trim() || isLoading
                      ? '#ccc'
                      : '#fff'
                  }
                />
              </TouchableOpacity>
            </View>
          )}
        </View>
      </KeyboardAvoidingView>

      {/* Task Creation Modal */}
      <Modal
        visible={showTaskMenu}
        animationType="slide"
        transparent={true}
        onRequestClose={() => setShowTaskMenu(false)}
      >
        <View
          style={[
            styles.modalOverlay,
            { backgroundColor: 'rgba(0,0,0,0.5)' },
          ]}
        >
          <View style={styles.modalContent}>
            <View style={styles.modalHeader}>
              <Text style={styles.modalTitle}>Create Task from Message</Text>
              <TouchableOpacity onPress={() => setShowTaskMenu(false)}>
                <MaterialCommunityIcons
                  name="close"
                  size={24}
                  color="#333"
                />
              </TouchableOpacity>
            </View>

            <View style={styles.modalBody}>
              <View style={styles.messagePreview}>
                <Text style={styles.messagePreviewLabel}>Message:</Text>
                <View style={styles.messagePreviewBox}>
                  <Text style={styles.messagePreviewText} numberOfLines={3}>
                    {selectedMessageForTask?.content}
                  </Text>
                </View>
              </View>

              <View style={styles.modalActions}>
                <TouchableOpacity
                  style={[styles.modalButton, { backgroundColor: '#f0f0f0' }]}
                  onPress={() => setShowTaskMenu(false)}
                >
                  <Text style={[styles.modalButtonText, { color: '#333' }]}>Cancel</Text>
                </TouchableOpacity>

                <TouchableOpacity
                  style={[styles.modalButton, { backgroundColor: '#4A90E2' }]}
                  onPress={handleCreateQuickTask}
                >
                  <MaterialCommunityIcons name="plus" size={18} color="#fff" />
                  <Text style={[styles.modalButtonText, { color: '#fff', marginLeft: 6 }]}>Create Task</Text>
                </TouchableOpacity>
              </View>
            </View>
          </View>
        </View>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  flex: {
    flex: 1,
  },
  header: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
  },
  errorBox: {
    backgroundColor: '#fee',
    borderColor: '#fcc',
    borderWidth: 1,
    marginHorizontal: 16,
    marginTop: 8,
    marginBottom: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderRadius: 6,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  errorText: {
    color: '#c33',
    fontSize: 13,
    flex: 1,
  },
  messagesList: {
    flexGrow: 1,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  messageContainer: {
    marginVertical: 6,
    flexDirection: 'column',
  },
  userMessageContainer: {
    alignItems: 'flex-end',
  },
  aiMessageContainer: {
    alignItems: 'flex-start',
  },
  messageBubble: {
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderRadius: 12,
    maxWidth: '80%',
  },
  userBubble: {
    backgroundColor: '#4A90E2',
  },
  aiBubble: {
    backgroundColor: '#f0f0f0',
  },
  messageText: {
    fontSize: 14,
    lineHeight: 20,
  },
  userText: {
    color: '#fff',
  },
  aiText: {
    color: '#333',
  },
  streamingIndicator: {
    marginTop: 4,
  },
  timestamp: {
    fontSize: 12,
    color: '#999',
    marginTop: 4,
    marginHorizontal: 4,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 20,
  },
  emptyTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#666',
    marginTop: 12,
  },
  emptySubtitle: {
    fontSize: 13,
    color: '#999',
    marginTop: 6,
    textAlign: 'center',
  },
  inputContainer: {
    paddingHorizontal: 12,
    paddingVertical: 12,
    borderTopWidth: 1,
    borderTopColor: '#eee',
    backgroundColor: '#fafafa',
  },
  loadingBox: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
  },
  loadingText: {
    fontSize: 13,
    color: '#666',
    marginLeft: 8,
  },
  inputWrapper: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    backgroundColor: '#fff',
    borderRadius: 24,
    paddingHorizontal: 12,
    paddingVertical: 4,
    borderWidth: 1,
    borderColor: '#ddd',
  },
  input: {
    flex: 1,
    paddingVertical: 10,
    paddingHorizontal: 0,
    fontSize: 14,
    maxHeight: 100,
  },
  voiceButton: {
    paddingHorizontal: 8,
    paddingVertical: 8,
  },
  sendButton: {
    backgroundColor: '#4A90E2',
    width: 36,
    height: 36,
    borderRadius: 18,
    justifyContent: 'center',
    alignItems: 'center',
    marginLeft: 8,
  },
  sendButtonDisabled: {
    backgroundColor: '#ddd',
  },
  headerActions: {
    flexDirection: 'row',
    gap: 12,
  },
  headerButton: {
    padding: 4,
  },
  modalOverlay: {
    flex: 1,
    justifyContent: 'flex-end',
  },
  modalContent: {
    backgroundColor: '#fff',
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    maxHeight: '70%',
    paddingTop: 16,
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingBottom: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#eee',
  },
  modalTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
  },
  modalBody: {
    padding: 16,
  },
  messagePreview: {
    marginBottom: 20,
  },
  messagePreviewLabel: {
    fontSize: 13,
    fontWeight: '600',
    color: '#666',
    marginBottom: 8,
  },
  messagePreviewBox: {
    backgroundColor: '#f5f5f5',
    borderRadius: 8,
    padding: 10,
    borderWidth: 1,
    borderColor: '#eee',
  },
  messagePreviewText: {
    fontSize: 13,
    color: '#333',
    lineHeight: 18,
  },
  modalActions: {
    flexDirection: 'row',
    gap: 12,
  },
  modalButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    borderRadius: 8,
  },
  modalButtonText: {
    fontSize: 14,
    fontWeight: '600',
  },
});
