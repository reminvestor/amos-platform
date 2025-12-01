import React, { useState } from 'react';
import {
  View,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  Keyboard,
} from 'react-native';
import { Send } from 'lucide-react-native';
import { useNavigation } from '@react-navigation/native';
import { useAppSelector, useAppDispatch } from '@store';
import { addMessage, setLoading, setError as setChatError, updateMessage } from '@store/slices/chatSlice';
import { getColors } from '@theme/colors';
import { ChatMessage } from '@types';
import * as chatService from '@services/chat';

interface Props {
  visible?: boolean;
}

export default function GlobalChatInput({ visible = true }: Props) {
  const navigation = useNavigation<any>();
  const dispatch = useAppDispatch();
  const { theme } = useAppSelector((state) => state.ui);
  const { isLoading } = useAppSelector((state) => state.chat);
  const colors = getColors(theme);
  const [inputText, setInputText] = useState('');

  if (!visible) return null;

  const handleSend = async () => {
    if (!inputText.trim() || isLoading) return;

    const messageContent = inputText.trim();
    setInputText('');
    Keyboard.dismiss();

    // Navigate to chat tab
    navigation.navigate('AMOS');

    // Create user message
    const userMessage: ChatMessage = {
      id: `${Date.now()}-user`,
      role: 'user',
      content: messageContent,
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
      for await (const chunk of chatService.sendChatMessage(messageContent)) {
        fullResponse += chunk;
        dispatch(updateMessage({ id: aiMessageId, updates: { content: fullResponse } }));
      }

      dispatch(updateMessage({ id: aiMessageId, updates: { is_streaming: false } }));
    } catch (err: any) {
      dispatch(setChatError(err.message || 'Failed to send message'));
    } finally {
      dispatch(setLoading(false));
    }
  };

  return (
    <View style={[styles.container, { backgroundColor: colors.surface, borderTopColor: colors.border }]}>
      <View style={[styles.inputWrapper, { backgroundColor: colors.background, borderColor: colors.border }]}>
        <TextInput
          style={[styles.input, { color: colors.text }]}
          placeholder="Ask AMOS anything..."
          placeholderTextColor={colors.textTertiary}
          value={inputText}
          onChangeText={setInputText}
          multiline
          maxLength={500}
          editable={!isLoading}
          returnKeyType="send"
          blurOnSubmit
          onSubmitEditing={handleSend}
        />
        <TouchableOpacity
          style={[
            styles.sendButton,
            { backgroundColor: colors.primary },
            (!inputText.trim() || isLoading) && { backgroundColor: colors.border },
          ]}
          onPress={handleSend}
          disabled={!inputText.trim() || isLoading}
        >
          <Send
            size={18}
            color={!inputText.trim() || isLoading ? colors.textTertiary : '#fff'}
          />
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    bottom: 60, // Above the tab bar
    left: 0,
    right: 0,
    paddingHorizontal: 12,
    paddingVertical: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 5,
  },
  inputWrapper: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    borderRadius: 20,
    paddingHorizontal: 12,
    paddingVertical: 4,
    borderWidth: 1,
  },
  input: {
    flex: 1,
    paddingVertical: 8,
    paddingHorizontal: 0,
    fontSize: 14,
    maxHeight: 80,
  },
  sendButton: {
    width: 32,
    height: 32,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
    marginLeft: 8,
  },
});
