import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
  LayoutAnimation,
  Platform,
  UIManager,
  ActivityIndicator,
} from 'react-native';
import { Bot, Loader, CheckCircle, AlertCircle, Clock, HelpCircle, Globe, Mail, Users, FileText, RefreshCw, Trash2, ChevronUp, ChevronDown } from 'lucide-react-native';
import { useAppSelector } from '@store';
import { getColors } from '@theme/colors';
import { useTaskMonitor, AgentTask } from '../contexts/TaskMonitorContext';
import { apiClient } from '@services/api';

// Enable LayoutAnimation on Android
if (Platform.OS === 'android' && UIManager.setLayoutAnimationEnabledExperimental) {
  UIManager.setLayoutAnimationEnabledExperimental(true);
}

function formatDuration(seconds: number): string {
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}m ${secs}s`;
  }
  const hours = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  return `${hours}h ${mins}m`;
}

function getStatusColor(status: AgentTask['status'], colors: any): string {
  switch (status) {
    case 'running':
    case 'processing':
      return colors.primary;
    case 'completed':
      return colors.success;
    case 'failed':
      return colors.error;
    case 'queued':
      return colors.warning;
    case 'waiting_for_input':
      return '#f97316'; // Orange
    default:
      return colors.textTertiary;
  }
}

function getStatusIcon(status: AgentTask['status']) {
  switch (status) {
    case 'running':
    case 'processing':
      return Loader;
    case 'completed':
      return CheckCircle;
    case 'failed':
      return AlertCircle;
    case 'queued':
      return Clock;
    case 'waiting_for_input':
      return HelpCircle;
    default:
      return HelpCircle;
  }
}

function getAgentIcon(agentType?: string) {
  if (!agentType) return Bot;
  const type = agentType.toLowerCase();
  if (type.includes('landing') || type.includes('page')) return Globe;
  if (type.includes('email') || type.includes('campaign')) return Mail;
  if (type.includes('contact')) return Users;
  if (type.includes('document')) return FileText;
  return Bot;
}

interface TaskItemProps {
  task: AgentTask;
  colors: any;
}

function TaskItem({ task, colors }: TaskItemProps) {
  const statusColor = getStatusColor(task.status, colors);
  const isActive = task.status === 'running' || task.status === 'processing';

  return (
    <View style={[styles.taskItem, { borderBottomColor: colors.border }]}>
      <View style={styles.taskHeader}>
        {/* Status indicator */}
        <View style={[styles.statusIndicator, { backgroundColor: statusColor }]}>
          {React.createElement(getStatusIcon(task.status), { size: 14, color: '#fff' })}
        </View>

        {/* Agent type badge */}
        {task.agent_type && (
          <View style={[styles.agentBadge, { backgroundColor: colors.primaryLight }]}>
            {React.createElement(getAgentIcon(task.agent_type), { size: 12, color: colors.primary })}
            <Text style={[styles.agentBadgeText, { color: colors.primary }]} numberOfLines={1}>
              {task.agent_type}
            </Text>
          </View>
        )}

        {/* Duration */}
        {task.duration !== undefined && (
          <Text style={[styles.duration, { color: colors.textTertiary }]}>
            {formatDuration(task.duration)}
          </Text>
        )}
      </View>

      {/* Message */}
      <Text style={[styles.taskMessage, { color: colors.text }]} numberOfLines={2}>
        {task.message || 'Processing...'}
      </Text>

      {/* Progress bar */}
      {isActive && (
        <View style={[styles.progressContainer, { backgroundColor: colors.border }]}>
          <View
            style={[
              styles.progressBar,
              { backgroundColor: statusColor, width: `${task.progress}%` },
            ]}
          />
        </View>
      )}

      {/* Error message */}
      {task.status === 'failed' && task.error && (
        <Text style={[styles.errorText, { color: colors.error }]} numberOfLines={1}>
          {task.error}
        </Text>
      )}
    </View>
  );
}

export default function TaskMonitor() {
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);
  const { tasks, activeTasks, isExpanded, setIsExpanded, clearCompletedTasks, addOrUpdateTask } = useTaskMonitor();
  const [isRefreshing, setIsRefreshing] = useState(false);

  // Don't render if no tasks
  if (tasks.length === 0) {
    return null;
  }

  const handleToggle = () => {
    LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
    setIsExpanded(!isExpanded);
  };

  const handleRefresh = async () => {
    try {
      setIsRefreshing(true);
      // Fetch active tasks from the server
      const response = await apiClient.get<{ tasks: AgentTask[] }>('/scout/active_tasks');
      if (response.tasks && Array.isArray(response.tasks)) {
        response.tasks.forEach((task) => {
          addOrUpdateTask(task);
        });
      }
    } catch (error) {
      console.error('Failed to refresh tasks:', error);
    } finally {
      setIsRefreshing(false);
    }
  };

  const activeCount = activeTasks.length;
  const completedCount = tasks.filter((t) => t.status === 'completed').length;
  const failedCount = tasks.filter((t) => t.status === 'failed').length;

  return (
    <View style={[styles.container, { backgroundColor: colors.surface, borderColor: colors.border }]}>
      {/* Header - always visible */}
      <TouchableOpacity
        style={[styles.header, { borderBottomColor: isExpanded ? colors.border : 'transparent' }]}
        onPress={handleToggle}
        activeOpacity={0.7}
      >
        <View style={styles.headerLeft}>
          <Bot size={18} color={colors.primary} />
          <Text style={[styles.headerTitle, { color: colors.text }]}>
            Agent Tasks
          </Text>

          {/* Badges */}
          {activeCount > 0 && (
            <View style={[styles.badge, { backgroundColor: colors.primary }]}>
              <Text style={styles.badgeText}>{activeCount}</Text>
            </View>
          )}
          {completedCount > 0 && (
            <View style={[styles.badge, { backgroundColor: colors.success }]}>
              <Text style={styles.badgeText}>{completedCount}</Text>
            </View>
          )}
          {failedCount > 0 && (
            <View style={[styles.badge, { backgroundColor: colors.error }]}>
              <Text style={styles.badgeText}>{failedCount}</Text>
            </View>
          )}
        </View>

        <View style={styles.headerRight}>
          {/* Refresh button */}
          {isExpanded && (
            <TouchableOpacity
              style={styles.clearButton}
              onPress={handleRefresh}
              disabled={isRefreshing}
            >
              {isRefreshing ? (
                <ActivityIndicator size="small" color={colors.textTertiary} />
              ) : (
                <RefreshCw size={16} color={colors.textTertiary} />
              )}
            </TouchableOpacity>
          )}

          {/* Clear completed button */}
          {(completedCount > 0 || failedCount > 0) && isExpanded && (
            <TouchableOpacity
              style={styles.clearButton}
              onPress={() => {
                LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
                clearCompletedTasks();
              }}
            >
              <Trash2 size={16} color={colors.textTertiary} />
            </TouchableOpacity>
          )}

          {isExpanded ? (
            <ChevronUp size={20} color={colors.textTertiary} />
          ) : (
            <ChevronDown size={20} color={colors.textTertiary} />
          )}
        </View>
      </TouchableOpacity>

      {/* Task list - only when expanded */}
      {isExpanded && (
        <View style={styles.taskList}>
          {tasks.map((task) => (
            <TaskItem key={task.task_id} task={task} colors={colors} />
          ))}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginHorizontal: 12,
    marginVertical: 8,
    borderRadius: 12,
    borderWidth: 1,
    overflow: 'hidden',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderBottomWidth: 1,
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  headerTitle: {
    fontSize: 14,
    fontWeight: '600',
  },
  headerRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  badge: {
    minWidth: 18,
    height: 18,
    borderRadius: 9,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 5,
  },
  badgeText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '600',
  },
  clearButton: {
    padding: 4,
  },
  taskList: {
    maxHeight: 200,
  },
  taskItem: {
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderBottomWidth: 1,
  },
  taskHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 6,
    gap: 8,
  },
  statusIndicator: {
    width: 22,
    height: 22,
    borderRadius: 11,
    justifyContent: 'center',
    alignItems: 'center',
  },
  agentBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    gap: 4,
    flex: 1,
  },
  agentBadgeText: {
    fontSize: 11,
    fontWeight: '500',
  },
  duration: {
    fontSize: 11,
    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
  },
  taskMessage: {
    fontSize: 13,
    lineHeight: 18,
    marginBottom: 6,
  },
  progressContainer: {
    height: 4,
    borderRadius: 2,
    overflow: 'hidden',
  },
  progressBar: {
    height: '100%',
    borderRadius: 2,
  },
  errorText: {
    fontSize: 11,
    marginTop: 4,
  },
});
