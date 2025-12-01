import React, { useState } from 'react';
import {
  View,
  Text,
  FlatList,
  StyleSheet,
  SafeAreaView,
  RefreshControl,
} from 'react-native';
import { Card, ActivityIndicator, Chip } from 'react-native-paper';
import { MotiView } from 'moti';
import { FilePlus, TrendingUp, Plug, Workflow, Settings, ChevronRight, AlertCircle } from 'lucide-react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAppDispatch, useAppSelector } from '@store';
import { fetchAgents } from '@store/slices/agentsSlice';
import { Agent } from '@types';
import { getColors } from '@theme/colors';

interface AgentListScreenProps {
  navigation: any;
}

export default function AgentListScreen({ navigation }: AgentListScreenProps) {
  const dispatch = useAppDispatch();
  const { list, isLoading, error } = useAppSelector((state) => state.agents);
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);
  const [refreshing, setRefreshing] = useState(false);

  // Load agents when screen is focused
  useFocusEffect(
    React.useCallback(() => {
      loadAgents();
    }, [])
  );

  const loadAgents = async () => {
    await dispatch(fetchAgents());
  };

  const handleRefresh = async () => {
    setRefreshing(true);
    await loadAgents();
    setRefreshing(false);
  };

  const handleAgentPress = (agent: Agent) => {
    navigation.navigate('AgentDetail', { agentId: agent.id });
  };

  const getIconForAgent = (agent: Agent) => {
    switch (agent.agent_type) {
      case 'content_generator':
        return FilePlus;
      case 'data_processor':
        return TrendingUp;
      case 'api_integration':
        return Plug;
      case 'workflow_automation':
        return Workflow;
      default:
        return Settings;
    }
  };

  const getLabelForAgentType = (agentType: string) => {
    const labelMap: Record<string, string> = {
      content_generator: 'Content Generator',
      data_processor: 'Data Processor',
      api_integration: 'API Integration',
      workflow_automation: 'Workflow Automation',
      custom: 'Custom Agent',
    };
    return labelMap[agentType] || agentType;
  };

  const renderAgentItem = ({ item, index }: { item: Agent; index: number }) => (
    <MotiView
      from={{ opacity: 0, translateY: 20 }}
      animate={{ opacity: 1, translateY: 0 }}
      transition={{ type: 'timing', duration: 350, delay: index * 50 }}
    >
      <Card
        style={[styles.agentCard, { backgroundColor: colors.card }]}
        onPress={() => handleAgentPress(item)}
        mode="outlined"
      >
      <Card.Content>
        <View style={styles.agentHeader}>
          <View
            style={[styles.agentIconContainer, { backgroundColor: colors.primary + '20' }]}
          >
            {React.createElement(getIconForAgent(item), { size: 24, color: colors.primary })}
          </View>
          <View style={styles.agentInfo}>
            <Text style={[styles.agentName, { color: colors.text }]}>{item.name}</Text>
            <Text style={[styles.agentType, { color: colors.textSecondary }]}>
              {getLabelForAgentType(item.agent_type)}
            </Text>
          </View>
          <ChevronRight size={24} color={colors.textSecondary} />
        </View>
        {item.description && (
          <Text style={[styles.agentDescription, { color: colors.textSecondary }]}>
            {item.description}
          </Text>
        )}
        {item.interactive && (
          <Chip
            icon="chat-processing"
            mode="flat"
            compact
            style={[styles.interactiveChip, { backgroundColor: colors.primary + '15' }]}
            textStyle={[styles.interactiveText, { color: colors.primary }]}
          >
            Interactive
          </Chip>
        )}
      </Card.Content>
    </Card>
    </MotiView>
  );

  const renderEmpty = () => (
    <View style={[styles.emptyContainer, { backgroundColor: colors.background }]}>
      <Settings size={64} color={colors.textSecondary} />
      <Text style={[styles.emptyText, { color: colors.textSecondary }]}>
        No agents available
      </Text>
      <Text style={[styles.emptySubtext, { color: colors.textSecondary }]}>
        Create agents in settings to use them here
      </Text>
    </View>
  );

  const renderError = () => (
    <View style={[styles.errorContainer, { backgroundColor: colors.background }]}>
      <AlertCircle size={64} color={colors.error} />
      <Text style={[styles.errorText, { color: colors.error }]}>
        Failed to load agents
      </Text>
      <Text style={[styles.errorSubtext, { color: colors.textSecondary }]}>
        {error || 'Please try again'}
      </Text>
    </View>
  );

  if (error) {
    return (
      <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
        {renderError()}
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <FlatList
        data={list}
        renderItem={renderAgentItem}
        keyExtractor={(item) => item.id}
        ListEmptyComponent={renderEmpty()}
        contentContainerStyle={styles.listContent}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={handleRefresh}
            tintColor={colors.primary}
          />
        }
      />
      {isLoading && list.length === 0 && (
        <View style={[styles.loadingContainer, { backgroundColor: colors.background }]}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  listContent: {
    padding: 12,
    paddingBottom: 20,
  },
  agentCard: {
    marginBottom: 12,
    borderRadius: 12,
  },
  agentHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
  },
  agentIconContainer: {
    width: 48,
    height: 48,
    borderRadius: 8,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  agentInfo: {
    flex: 1,
  },
  agentName: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 4,
  },
  agentType: {
    fontSize: 12,
  },
  agentDescription: {
    fontSize: 13,
    lineHeight: 18,
    marginBottom: 8,
  },
  interactiveChip: {
    alignSelf: 'flex-start',
    marginTop: 4,
  },
  interactiveText: {
    fontSize: 11,
    fontWeight: '500',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 24,
    paddingTop: 100,
  },
  emptyText: {
    fontSize: 16,
    fontWeight: '600',
    marginTop: 16,
    textAlign: 'center',
  },
  emptySubtext: {
    fontSize: 14,
    marginTop: 8,
    textAlign: 'center',
  },
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 24,
  },
  errorText: {
    fontSize: 16,
    fontWeight: '600',
    marginTop: 16,
    textAlign: 'center',
  },
  errorSubtext: {
    fontSize: 14,
    marginTop: 8,
    textAlign: 'center',
  },
  loadingContainer: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'center',
    alignItems: 'center',
  },
});
