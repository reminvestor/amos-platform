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
import { MessageCircle, X, Lightbulb, Mic, Send, Plus, FileText, Users, Mail, CheckSquare, Globe, CloudUpload, HelpCircle, ChevronRight } from 'lucide-react-native';
import { useNavigation, useRoute } from '@react-navigation/native';
import * as chatService from '@services/chat';
import { setSSEEventCallback, SSEEvent } from '@services/chat';
import { ChatMessage } from '@types';
import { formatRelativeTime } from '@utils/formatters';
import { useAppSelector, useAppDispatch } from '@store';
import {
  setMessages,
  addMessage,
  updateMessage,
  clearMessages,
  setLoading,
  setError as setChatError,
} from '@store/slices/chatSlice';
import { getColors } from '@theme/colors';
import { useVoiceInput } from '../../hooks/useVoiceInput';
import TaskMonitor from '@components/TaskMonitor';
import { useTaskMonitor, parseTaskEvent } from '../../contexts/TaskMonitorContext';

// Quick action options for the idea menu
const QUICK_ACTIONS = [
  { id: 'documents', label: 'Show documents', Icon: FileText, message: 'Show my documents' },
  { id: 'contacts', label: 'Show contacts', Icon: Users, message: 'Show my contacts' },
  { id: 'campaigns', label: 'Show campaigns', Icon: Mail, message: 'Show my campaigns' },
  { id: 'tasks', label: 'Show my tasks', Icon: CheckSquare, message: 'Show my tasks' },
  { id: 'landing-page', label: 'Create a landing page', Icon: Globe, message: 'Help me create a landing page' },
  { id: 'upload', label: 'Upload a document', Icon: CloudUpload, message: 'I want to upload a document' },
  { id: 'help', label: 'What can you do?', Icon: HelpCircle, message: 'What can you help me with?' },
];

export default function ChatScreen() {
  const navigation = useNavigation<any>();
  const route = useRoute<any>();
  const dispatch = useAppDispatch();
  const { theme } = useAppSelector((state) => state.ui);
  const { messages, isLoading, error } = useAppSelector((state) => state.chat);
  const colors = getColors(theme);
  const [inputText, setInputText] = useState('');
  const [isListening, setIsListening] = useState(false);
  const [showTaskMenu, setShowTaskMenu] = useState(false);
  const [showQuickActions, setShowQuickActions] = useState(false);
  const [selectedMessageForTask, setSelectedMessageForTask] = useState<ChatMessage | null>(null);
  const [historyLoaded, setHistoryLoaded] = useState(false);
  const flatListRef = useRef<FlatList>(null);
  const inputRef = useRef<TextInput>(null);

  // Task monitor integration
  const { addOrUpdateTask } = useTaskMonitor();

  // Set up SSE event callback for task updates
  useEffect(() => {
    const handleSSEEvent = (event: SSEEvent) => {
      // Handle task events
      const taskEvent = parseTaskEvent(event);
      if (taskEvent) {
        addOrUpdateTask(taskEvent);
      }
    };

    setSSEEventCallback(handleSSEEvent);

    // Cleanup on unmount
    return () => {
      setSSEEventCallback(null);
    };
  }, [addOrUpdateTask]);

  // Load chat history on mount (only if not already loaded)
  useEffect(() => {
    if (!historyLoaded && messages.length === 0) {
      loadChatHistory();
    }
  }, [historyLoaded, messages.length]);

  // Handle new conversation request (from AppHeader)
  useEffect(() => {
    if (route.params?.resetChat) {
      handleClearConversation();
      // Clear the param so it doesn't trigger again
      navigation.setParams({ resetChat: undefined });
    }
  }, [route.params?.resetChat]);

  const handleClearConversation = async () => {
    try {
      // Clear local messages immediately for responsiveness
      dispatch(clearMessages());
      setHistoryLoaded(false);
      // Call API to clear server-side history
      await chatService.clearConversation();
    } catch (err: any) {
      console.error('Error clearing conversation:', err);
      // Don't show error - local clear still worked
    }
  };

  // Scroll to bottom when new messages arrive
  useEffect(() => {
    if (messages.length > 0) {
      flatListRef.current?.scrollToEnd({ animated: true });
    }
  }, [messages]);

  const loadChatHistory = async () => {
    try {
      dispatch(setLoading(true));
      const response = await chatService.getChatHistory({ perPage: 50 });
      // Response now returns { messages, hasMore, total }
      const history = response.messages || [];
      dispatch(setMessages(
        history.map((msg) => ({
          ...msg,
          id: msg.id || `${Date.now()}-${Math.random()}`,
        }))
      ));
      dispatch(setChatError(null));
      setHistoryLoaded(true);
    } catch (err: any) {
      dispatch(setChatError('Failed to load chat history'));
      console.error('Error loading history:', err);
    } finally {
      dispatch(setLoading(false));
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

    dispatch(addMessage(userMessage));
    setInputText('');
    dispatch(setChatError(null));

    try {
      dispatch(setLoading(true));

      // Create AI message placeholder
      const aiMessageId = `${Date.now()}-ai`;
      const aiMessage: ChatMessage = {
        id: aiMessageId,
        role: 'assistant',
        content: '',
        timestamp: new Date().toISOString(),
        is_streaming: true,
      };

      dispatch(addMessage(aiMessage));

      // Stream response
      let fullResponse = '';
      for await (const chunk of chatService.sendChatMessage(userMessage.content)) {
        fullResponse += chunk;

        // Update message with streaming content
        dispatch(updateMessage({ id: aiMessageId, updates: { content: fullResponse } }));
      }

      // Mark as complete
      dispatch(updateMessage({ id: aiMessageId, updates: { is_streaming: false } }));
    } catch (err: any) {
      dispatch(setChatError(err.message || 'Failed to send message'));
    } finally {
      dispatch(setLoading(false));
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

  const handleQuickAction = async (action: typeof QUICK_ACTIONS[0]) => {
    setShowQuickActions(false);
    // Set the message and send it
    const message = action.message;

    const userMessage: ChatMessage = {
      id: `${Date.now()}-user`,
      role: 'user',
      content: message,
      timestamp: new Date().toISOString(),
    };

    dispatch(addMessage(userMessage));
    dispatch(setChatError(null));

    try {
      dispatch(setLoading(true));

      // Create AI message placeholder
      const aiMessageId = `${Date.now()}-ai`;
      const aiMessage: ChatMessage = {
        id: aiMessageId,
        role: 'assistant',
        content: '',
        timestamp: new Date().toISOString(),
        is_streaming: true,
      };

      dispatch(addMessage(aiMessage));

      // Stream response
      let fullResponse = '';
      for await (const chunk of chatService.sendChatMessage(message)) {
        fullResponse += chunk;

        // Update message with streaming content
        dispatch(updateMessage({ id: aiMessageId, updates: { content: fullResponse } }));
      }

      // Mark as complete
      dispatch(updateMessage({ id: aiMessageId, updates: { is_streaming: false } }));
    } catch (err: any) {
      dispatch(setChatError(err.message || 'Failed to send message'));
    } finally {
      dispatch(setLoading(false));
    }
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
            isUser
              ? { backgroundColor: colors.primary }
              : { backgroundColor: colors.surface },
          ]}
        >
          <Text
            style={[
              styles.messageText,
              isUser
                ? { color: '#fff' }
                : { color: colors.text },
            ]}
          >
            {item.content}
          </Text>
          {item.is_streaming && (
            <ActivityIndicator
              size="small"
              color={isUser ? '#fff' : colors.text}
              style={styles.streamingIndicator}
            />
          )}
        </View>
        <Text style={[styles.timestamp, { color: colors.textTertiary }]}>
          {formatRelativeTime(item.timestamp)}
        </Text>
      </View>
    );
  };

  const renderEmpty = () => (
    <View style={styles.emptyContainer}>
      <MessageCircle size={64} color={colors.textTertiary} />
      <Text style={[styles.emptyTitle, { color: colors.textSecondary }]}>No messages yet</Text>
      <Text style={[styles.emptySubtitle, { color: colors.textTertiary }]}>
        Start a conversation with the AI assistant
      </Text>
    </View>
  );

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.flex}
        keyboardVerticalOffset={90}
      >
        {/* Error message */}
        {error && (
          <View style={[styles.errorBox, { backgroundColor: colors.errorLight, borderColor: colors.error }]}>
            <Text style={[styles.errorText, { color: colors.error }]}>{error}</Text>
            <TouchableOpacity onPress={() => dispatch(setChatError(null))}>
              <X size={20} color={colors.error} />
            </TouchableOpacity>
          </View>
        )}

        {/* Task Monitor - shows active agent tasks */}
        <TaskMonitor />

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
        <View style={[styles.inputContainer, { borderTopColor: colors.border, backgroundColor: colors.surface }]}>
          {isLoading ? (
            <View style={styles.loadingBox}>
              <ActivityIndicator size="small" color={colors.primary} />
              <Text style={[styles.loadingText, { color: colors.textSecondary }]}>AI is thinking...</Text>
            </View>
          ) : (
            <View style={[styles.inputWrapper, { backgroundColor: colors.background, borderColor: colors.border }]}>
              <TouchableOpacity
                style={styles.ideaButton}
                onPress={() => setShowQuickActions(true)}
                disabled={isLoading}
              >
                <Lightbulb size={22} color={colors.primary} />
              </TouchableOpacity>

              <TextInput
                ref={inputRef}
                style={[styles.input, { color: colors.text }]}
                placeholder="Ask me anything..."
                placeholderTextColor={colors.textTertiary}
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
                <Mic
                  size={20}
                  color={isListening ? colors.primary : colors.textSecondary}
                />
              </TouchableOpacity>

              <TouchableOpacity
                style={[
                  styles.sendButton,
                  { backgroundColor: colors.primary },
                  (!inputText.trim() || isLoading) && { backgroundColor: colors.border },
                ]}
                onPress={handleSendMessage}
                disabled={!inputText.trim() || isLoading}
              >
                <Send
                  size={20}
                  color={
                    !inputText.trim() || isLoading
                      ? colors.textTertiary
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
          <View style={[styles.modalContent, { backgroundColor: colors.background }]}>
            <View style={[styles.modalHeader, { borderBottomColor: colors.border }]}>
              <Text style={[styles.modalTitle, { color: colors.text }]}>Create Task from Message</Text>
              <TouchableOpacity onPress={() => setShowTaskMenu(false)}>
                <X size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            <View style={styles.modalBody}>
              <View style={styles.messagePreview}>
                <Text style={[styles.messagePreviewLabel, { color: colors.textSecondary }]}>Message:</Text>
                <View style={[styles.messagePreviewBox, { backgroundColor: colors.surface, borderColor: colors.border }]}>
                  <Text style={[styles.messagePreviewText, { color: colors.text }]} numberOfLines={3}>
                    {selectedMessageForTask?.content}
                  </Text>
                </View>
              </View>

              <View style={styles.modalActions}>
                <TouchableOpacity
                  style={[styles.modalButton, { backgroundColor: colors.surface }]}
                  onPress={() => setShowTaskMenu(false)}
                >
                  <Text style={[styles.modalButtonText, { color: colors.text }]}>Cancel</Text>
                </TouchableOpacity>

                <TouchableOpacity
                  style={[styles.modalButton, { backgroundColor: colors.primary }]}
                  onPress={handleCreateQuickTask}
                >
                  <Plus size={18} color="#fff" />
                  <Text style={[styles.modalButtonText, { color: '#fff', marginLeft: 6 }]}>Create Task</Text>
                </TouchableOpacity>
              </View>
            </View>
          </View>
        </View>
      </Modal>

      {/* Quick Actions Modal */}
      <Modal
        visible={showQuickActions}
        animationType="slide"
        transparent={true}
        onRequestClose={() => setShowQuickActions(false)}
      >
        <TouchableOpacity
          style={styles.modalOverlay}
          activeOpacity={1}
          onPress={() => setShowQuickActions(false)}
        >
          <View style={[styles.quickActionsContent, { backgroundColor: colors.background }]}>
            <View style={[styles.quickActionsHeader, { borderBottomColor: colors.border }]}>
              <Lightbulb size={20} color={colors.primary} />
              <Text style={[styles.quickActionsTitle, { color: colors.text }]}>Quick Actions</Text>
            </View>

            {QUICK_ACTIONS.map((action) => (
              <TouchableOpacity
                key={action.id}
                style={[styles.quickActionItem, { borderBottomColor: colors.border }]}
                onPress={() => handleQuickAction(action)}
                activeOpacity={0.7}
              >
                <View style={[styles.quickActionIconContainer, { backgroundColor: colors.primaryLight }]}>
                  <action.Icon size={22} color={colors.primary} />
                </View>
                <Text style={[styles.quickActionLabel, { color: colors.text }]}>{action.label}</Text>
                <ChevronRight size={20} color={colors.textTertiary} />
              </TouchableOpacity>
            ))}
          </View>
        </TouchableOpacity>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  flex: {
    flex: 1,
  },
  header: {
    paddingHorizontal: 16,
    paddingVertical: 12,
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
  headerTitle: {
    fontSize: 18,
    fontWeight: '600',
  },
  errorBox: {
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
  ideaButton: {
    paddingHorizontal: 4,
    paddingVertical: 8,
    marginRight: 4,
  },
  quickActionsContent: {
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    paddingBottom: 32,
  },
  quickActionsHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: 1,
    gap: 8,
  },
  quickActionsTitle: {
    fontSize: 16,
    fontWeight: '600',
  },
  quickActionItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: 1,
  },
  quickActionIconContainer: {
    width: 40,
    height: 40,
    borderRadius: 10,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  quickActionLabel: {
    flex: 1,
    fontSize: 15,
    fontWeight: '500',
  },
});
