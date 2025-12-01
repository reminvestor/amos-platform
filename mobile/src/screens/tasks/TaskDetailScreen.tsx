import React, { useState, useEffect } from 'react';
import {
  View,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  ActivityIndicator,
  RefreshControl,
  Alert,
  Modal,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { ArrowLeft, Trash2, AlertCircle, CheckCircle, Clock, Circle, CircleSlash, ChevronRight, Calendar, Pencil, Trash, X, Check, Link2 } from 'lucide-react-native';
import { useAppDispatch, useAppSelector } from '@store';
import {
  fetchTaskDetail,
  updateTaskAsync,
  deleteTaskAsync,
  clearCurrentTask,
} from '@store/slices/tasksSlice';
import { getColors } from '@theme/colors';
import { StyledText } from '@components/StyledText';
import { Task } from '@types';

interface TaskDetailScreenProps {
  navigation: any;
  route: any;
}

export default function TaskDetailScreen({
  navigation,
  route,
}: TaskDetailScreenProps) {
  const insets = useSafeAreaInsets();
  const dispatch = useAppDispatch();
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  const { taskId } = route.params;
  const { current: task, isLoading, error } = useAppSelector(
    (state) => state.tasks
  );

  const [isRefreshing, setIsRefreshing] = useState(false);
  const [showStatusModal, setShowStatusModal] = useState(false);
  const [showPriorityModal, setShowPriorityModal] = useState(false);
  const [selectedStatus, setSelectedStatus] = useState(task?.status || 'pending');
  const [selectedPriority, setSelectedPriority] = useState(task?.priority || 'medium');
  const [isUpdating, setIsUpdating] = useState(false);

  useEffect(() => {
    loadTaskDetail();
  }, [taskId]);

  const loadTaskDetail = async () => {
    try {
      await dispatch(fetchTaskDetail(taskId)).unwrap();
    } catch (err) {
      console.error('Error loading task:', err);
    }
  };

  const handleRefresh = async () => {
    setIsRefreshing(true);
    try {
      await dispatch(fetchTaskDetail(taskId)).unwrap();
    } catch (err) {
      console.error('Error refreshing:', err);
    } finally {
      setIsRefreshing(false);
    }
  };

  const handleStatusChange = async (newStatus: string) => {
    if (!task) return;
    setIsUpdating(true);
    try {
      await dispatch(
        updateTaskAsync({
          id: task.id,
          data: { status: newStatus },
        })
      ).unwrap();
      setSelectedStatus(newStatus);
      setShowStatusModal(false);
    } catch (err) {
      Alert.alert('Error', 'Failed to update task status');
      console.error('Error updating status:', err);
    } finally {
      setIsUpdating(false);
    }
  };

  const handlePriorityChange = async (newPriority: string) => {
    if (!task) return;
    setIsUpdating(true);
    try {
      await dispatch(
        updateTaskAsync({
          id: task.id,
          data: { priority: newPriority },
        })
      ).unwrap();
      setSelectedPriority(newPriority);
      setShowPriorityModal(false);
    } catch (err) {
      Alert.alert('Error', 'Failed to update task priority');
      console.error('Error updating priority:', err);
    } finally {
      setIsUpdating(false);
    }
  };

  const handleDelete = () => {
    if (!task) return;
    Alert.alert(
      'Delete Task',
      'Are you sure you want to delete this task? This action cannot be undone.',
      [
        { text: 'Cancel', onPress: () => {}, style: 'cancel' },
        {
          text: 'Delete',
          onPress: async () => {
            try {
              await dispatch(deleteTaskAsync(task.id)).unwrap();
              dispatch(clearCurrentTask());
              navigation.goBack();
            } catch (err) {
              Alert.alert('Error', 'Failed to delete task');
              console.error('Error deleting task:', err);
            }
          },
          style: 'destructive',
        },
      ]
    );
  };

  const formatDate = (dateString?: string) => {
    if (!dateString) return 'Not set';
    return new Date(dateString).toLocaleDateString('en-US', {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
  };

  const formatDateTime = (dateString?: string) => {
    if (!dateString) return 'Not set';
    return new Date(dateString).toLocaleString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  const getPriorityColor = (priority: string) => {
    switch (priority) {
      case 'high':
        return colors.error;
      case 'medium':
        return colors.warning;
      case 'low':
        return colors.success;
      default:
        return colors.textSecondary;
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'completed':
        return colors.success;
      case 'in_progress':
        return colors.info;
      case 'pending':
        return colors.warning;
      case 'cancelled':
        return colors.error;
      default:
        return colors.textSecondary;
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'completed':
        return CheckCircle;
      case 'in_progress':
        return Clock;
      case 'pending':
        return Circle;
      case 'cancelled':
        return CircleSlash;
      default:
        return Circle;
    }
  };

  if (isLoading && !isRefreshing) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      </View>
    );
  }

  if (!task) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centerContainer}>
          <StyledText style={[styles.errorText, { color: colors.text }]}>
            Task not found
          </StyledText>
          <TouchableOpacity
            onPress={() => navigation.goBack()}
            style={[styles.retryButton, { backgroundColor: colors.primary }]}
          >
            <StyledText style={[styles.retryButtonText]}>
              Go Back
            </StyledText>
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  const isOverdue =
    task.due_date &&
    task.status !== 'completed' &&
    new Date(task.due_date) < new Date();

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={handleRefresh}
            tintColor={colors.primary}
          />
        }
      >
        {/* Header */}
        <View style={[styles.header, { paddingTop: insets.top }]}>
          <TouchableOpacity onPress={() => navigation.goBack()}>
            <ArrowLeft size={24} color={colors.text} />
          </TouchableOpacity>
          <View style={{ flex: 1 }} />
          <TouchableOpacity
            onPress={handleDelete}
            disabled={isUpdating}
          >
            <Trash2 size={24} color={colors.error} />
          </TouchableOpacity>
        </View>

        {/* Error State */}
        {error && (
          <View style={[styles.errorContainer, { backgroundColor: colors.error }]}>
            <AlertCircle size={20} color="#fff" />
            <StyledText style={[styles.errorText, { color: '#fff' }]}>
              {error}
            </StyledText>
            <TouchableOpacity onPress={loadTaskDetail}>
              <StyledText style={[styles.retryText, { color: '#fff' }]}>
                Retry
              </StyledText>
            </TouchableOpacity>
          </View>
        )}

        {/* Title */}
        <View style={styles.titleSection}>
          <StyledText
            style={[
              styles.taskTitle,
              {
                color: colors.text,
                textDecorationLine:
                  task.status === 'completed' ? 'line-through' : 'none',
              },
            ]}
          >
            {task.title}
          </StyledText>
          {task.description && (
            <StyledText style={[styles.description, { color: colors.textSecondary }]}>
              {task.description}
            </StyledText>
          )}
        </View>

        {/* Status and Priority Cards */}
        <View style={styles.statusPriorityContainer}>
          {/* Status Card */}
          <TouchableOpacity
            testID="status-modal-trigger"
            disabled={isUpdating}
            onPress={() => setShowStatusModal(true)}
            style={[
              styles.statusCard,
              {
                backgroundColor: colors.surface,
                borderColor: colors.border,
              },
            ]}
          >
            {React.createElement(getStatusIcon(task.status), {
              size: 28,
              color: getStatusColor(task.status),
            })}
            <View style={{ flex: 1, marginLeft: 8 }}>
              <StyledText style={[styles.cardLabel, { color: colors.textSecondary }]}>
                Status
              </StyledText>
              <StyledText style={[styles.cardValue, { color: colors.text }]}>
                {task.status.replace('_', ' ')}
              </StyledText>
            </View>
            <ChevronRight size={20} color={colors.textSecondary} />
          </TouchableOpacity>

          {/* Priority Card */}
          <TouchableOpacity
            testID="priority-modal-trigger"
            disabled={isUpdating}
            onPress={() => setShowPriorityModal(true)}
            style={[
              styles.statusCard,
              {
                backgroundColor: colors.surface,
                borderColor: colors.border,
              },
            ]}
          >
            <View
              style={[
                styles.priorityIndicator,
                { backgroundColor: getPriorityColor(task.priority) },
              ]}
            />
            <View style={{ flex: 1, marginLeft: 8 }}>
              <StyledText style={[styles.cardLabel, { color: colors.textSecondary }]}>
                Priority
              </StyledText>
              <StyledText style={[styles.cardValue, { color: colors.text }]}>
                {task.priority}
              </StyledText>
            </View>
            <ChevronRight size={20} color={colors.textSecondary} />
          </TouchableOpacity>
        </View>

        {/* Due Date Card */}
        <View
          style={[
            styles.infoCard,
            {
              backgroundColor: colors.surface,
              borderColor: isOverdue ? colors.error : colors.border,
              borderLeftColor: isOverdue ? colors.error : colors.primary,
              borderLeftWidth: 3,
            },
          ]}
        >
          <Calendar size={20} color={isOverdue ? colors.error : colors.primary} />
          <View style={{ flex: 1, marginLeft: 12 }}>
            <StyledText style={[styles.cardLabel, { color: colors.textSecondary }]}>
              Due Date
            </StyledText>
            <StyledText
              style={[
                styles.cardValue,
                { color: isOverdue ? colors.error : colors.text },
              ]}
            >
              {formatDate(task.due_date)}
            </StyledText>
            {isOverdue && (
              <StyledText style={[styles.overdueText, { color: colors.error }]}>
                Overdue
              </StyledText>
            )}
          </View>
        </View>

        {/* Task Details Section */}
        <View style={styles.detailsSection}>
          <StyledText style={[styles.sectionTitle, { color: colors.text }]}>
            Details
          </StyledText>

          {/* Created Date */}
          <View style={[styles.detailRow, { borderBottomColor: colors.border }]}>
            <StyledText style={[styles.detailLabel, { color: colors.textSecondary }]}>
              Created
            </StyledText>
            <StyledText style={[styles.detailValue, { color: colors.text }]}>
              {formatDateTime(task.created_at)}
            </StyledText>
          </View>

          {/* Updated Date */}
          <View style={[styles.detailRow, { borderBottomColor: colors.border }]}>
            <StyledText style={[styles.detailLabel, { color: colors.textSecondary }]}>
              Updated
            </StyledText>
            <StyledText style={[styles.detailValue, { color: colors.text }]}>
              {formatDateTime(task.updated_at)}
            </StyledText>
          </View>

          {/* Completed Date */}
          {task.completed_at && (
            <View style={[styles.detailRow, { borderBottomColor: colors.border }]}>
              <StyledText style={[styles.detailLabel, { color: colors.textSecondary }]}>
                Completed
              </StyledText>
              <StyledText style={[styles.detailValue, { color: colors.text }]}>
                {formatDateTime(task.completed_at)}
              </StyledText>
            </View>
          )}

          {/* Assigned To */}
          {task.assigned_to && (
            <View style={[styles.detailRow, { borderBottomColor: colors.border }]}>
              <StyledText style={[styles.detailLabel, { color: colors.textSecondary }]}>
                Assigned To
              </StyledText>
              <StyledText style={[styles.detailValue, { color: colors.text }]}>
                {task.assigned_to}
              </StyledText>
            </View>
          )}
        </View>

        {/* Tags Section */}
        {task.tags && task.tags.length > 0 && (
          <View style={styles.tagsSection}>
            <StyledText style={[styles.sectionTitle, { color: colors.text }]}>
              Tags
            </StyledText>
            <View style={styles.tagsContainer}>
              {task.tags.map((tag, index) => (
                <View
                  key={index}
                  style={[
                    styles.tag,
                    { backgroundColor: colors.primary, opacity: 0.15 },
                  ]}
                >
                  <StyledText
                    style={[styles.tagText, { color: colors.primary }]}
                  >
                    {tag}
                  </StyledText>
                </View>
              ))}
            </View>
          </View>
        )}

        {/* Related Entity */}
        {task.related_entity && task.related_entity.id && (
          <View
            style={[
              styles.relatedEntityCard,
              {
                backgroundColor: colors.surface,
                borderColor: colors.border,
              },
            ]}
          >
            <Link2 size={20} color={colors.primary} />
            <View style={{ flex: 1, marginLeft: 12 }}>
              <StyledText style={[styles.cardLabel, { color: colors.textSecondary }]}>
                Related {task.related_entity.type}
              </StyledText>
              <TouchableOpacity
                onPress={() => {
                  // Navigate to related entity detail screen
                  const screenMap: Record<string, string> = {
                    campaign: 'CampaignDetail',
                    contact: 'ContactDetail',
                    landing_page: 'LandingPageDetail',
                  };
                  const screenName = screenMap[task.related_entity!.type];
                  if (screenName && task.related_entity!.id) {
                    navigation.navigate(screenName, {
                      id: task.related_entity!.id,
                    });
                  }
                }}
              >
                <StyledText style={[styles.linkText, { color: colors.primary }]}>
                  View {task.related_entity.type} →
                </StyledText>
              </TouchableOpacity>
            </View>
          </View>
        )}

        {/* Action Buttons */}
        <View style={styles.actionButtons}>
          <TouchableOpacity
            onPress={() =>
              navigation.navigate('TaskEdit', {
                mode: 'edit',
                taskId: task.id,
              })
            }
            disabled={isUpdating}
            style={[
              styles.actionButton,
              { backgroundColor: colors.primary },
            ]}
          >
            <Pencil size={18} color="#fff" />
            <StyledText style={[styles.actionButtonText, { color: '#fff' }]}>
              Edit
            </StyledText>
          </TouchableOpacity>

          <TouchableOpacity
            onPress={handleDelete}
            disabled={isUpdating}
            style={[
              styles.actionButton,
              { backgroundColor: colors.error },
            ]}
          >
            <Trash size={18} color="#fff" />
            <StyledText style={[styles.actionButtonText, { color: '#fff' }]}>
              Delete
            </StyledText>
          </TouchableOpacity>
        </View>

        <View style={{ height: insets.bottom + 32 }} />
      </ScrollView>

      {/* Status Modal */}
      <Modal
        visible={showStatusModal}
        animationType="slide"
        transparent={true}
        onRequestClose={() => setShowStatusModal(false)}
      >
        <View
          style={[
            styles.modalOverlay,
            { backgroundColor: 'rgba(0,0,0,0.5)' },
          ]}
        >
          <View
            style={[
              styles.modalContent,
              { backgroundColor: colors.background },
            ]}
          >
            <View
              style={[
                styles.modalHeader,
                { borderBottomColor: colors.border },
              ]}
            >
              <StyledText style={[styles.modalTitle, { color: colors.text }]}>
                Change Status
              </StyledText>
              <TouchableOpacity
                onPress={() => setShowStatusModal(false)}
                disabled={isUpdating}
              >
                <X size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            <View style={styles.modalBody}>
              {['pending', 'in_progress', 'completed', 'cancelled'].map((status) => (
                <TouchableOpacity
                  key={status}
                  testID={`status-option-${status}`}
                  onPress={() => handleStatusChange(status)}
                  disabled={isUpdating}
                  style={[
                    styles.modalOption,
                    {
                      backgroundColor:
                        selectedStatus === status
                          ? getStatusColor(status) + '20'
                          : 'transparent',
                      borderBottomColor: colors.border,
                    },
                  ]}
                >
                  {React.createElement(getStatusIcon(status), {
                    size: 24,
                    color: getStatusColor(status),
                  })}
                  <StyledText
                    style={[
                      styles.modalOptionText,
                      {
                        color: colors.text,
                        fontWeight:
                          selectedStatus === status ? '600' : '400',
                      },
                    ]}
                  >
                    {status.replace('_', ' ')}
                  </StyledText>
                  {selectedStatus === status && (
                    <Check
                      size={20}
                      color={getStatusColor(status)}
                      style={{ marginLeft: 'auto' }}
                    />
                  )}
                </TouchableOpacity>
              ))}
            </View>
          </View>
        </View>
      </Modal>

      {/* Priority Modal */}
      <Modal
        visible={showPriorityModal}
        animationType="slide"
        transparent={true}
        onRequestClose={() => setShowPriorityModal(false)}
      >
        <View
          style={[
            styles.modalOverlay,
            { backgroundColor: 'rgba(0,0,0,0.5)' },
          ]}
        >
          <View
            style={[
              styles.modalContent,
              { backgroundColor: colors.background },
            ]}
          >
            <View
              style={[
                styles.modalHeader,
                { borderBottomColor: colors.border },
              ]}
            >
              <StyledText style={[styles.modalTitle, { color: colors.text }]}>
                Change Priority
              </StyledText>
              <TouchableOpacity
                onPress={() => setShowPriorityModal(false)}
                disabled={isUpdating}
              >
                <X size={24} color={colors.text} />
              </TouchableOpacity>
            </View>

            <View style={styles.modalBody}>
              {['low', 'medium', 'high'].map((priority) => (
                <TouchableOpacity
                  key={priority}
                  testID={`priority-option-${priority}`}
                  onPress={() => handlePriorityChange(priority)}
                  disabled={isUpdating}
                  style={[
                    styles.modalOption,
                    {
                      backgroundColor:
                        selectedPriority === priority
                          ? getPriorityColor(priority) + '20'
                          : 'transparent',
                      borderBottomColor: colors.border,
                    },
                  ]}
                >
                  <View
                    style={[
                      styles.priorityIndicator,
                      { backgroundColor: getPriorityColor(priority) },
                    ]}
                  />
                  <StyledText
                    style={[
                      styles.modalOptionText,
                      {
                        color: colors.text,
                        fontWeight:
                          selectedPriority === priority ? '600' : '400',
                      },
                    ]}
                  >
                    {priority}
                  </StyledText>
                  {selectedPriority === priority && (
                    <Check
                      size={20}
                      color={getPriorityColor(priority)}
                      style={{ marginLeft: 'auto' }}
                    />
                  )}
                </TouchableOpacity>
              ))}
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  content: {
    paddingHorizontal: 16,
    paddingBottom: 32,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
    paddingBottom: 16,
  },
  errorContainer: {
    marginBottom: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderRadius: 8,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  errorText: {
    fontSize: 14,
    fontWeight: '500',
  },
  retryText: {
    fontSize: 12,
    fontWeight: '600',
    textDecorationLine: 'underline',
  },
  retryButton: {
    marginTop: 16,
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 8,
  },
  retryButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  titleSection: {
    marginBottom: 24,
  },
  taskTitle: {
    fontSize: 24,
    fontWeight: '700',
    marginBottom: 8,
  },
  description: {
    fontSize: 14,
    lineHeight: 20,
  },
  statusPriorityContainer: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 20,
  },
  statusCard: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 8,
    borderWidth: 1,
    paddingHorizontal: 12,
    paddingVertical: 12,
  },
  priorityIndicator: {
    width: 12,
    height: 12,
    borderRadius: 6,
  },
  cardLabel: {
    fontSize: 12,
    marginBottom: 2,
  },
  cardValue: {
    fontSize: 15,
    fontWeight: '600',
  },
  infoCard: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 8,
    borderWidth: 1,
    padding: 12,
    marginBottom: 20,
  },
  overdueText: {
    fontSize: 11,
    fontWeight: '600',
    marginTop: 2,
  },
  detailsSection: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 12,
  },
  detailRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: 1,
  },
  detailLabel: {
    fontSize: 14,
    fontWeight: '500',
  },
  detailValue: {
    fontSize: 14,
    fontWeight: '500',
  },
  tagsSection: {
    marginBottom: 24,
  },
  tagsContainer: {
    flexDirection: 'row',
    gap: 8,
    flexWrap: 'wrap',
  },
  tag: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 4,
  },
  tagText: {
    fontSize: 12,
    fontWeight: '500',
  },
  relatedEntityCard: {
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 8,
    borderWidth: 1,
    padding: 12,
    marginBottom: 24,
  },
  linkText: {
    fontSize: 14,
    fontWeight: '600',
    marginTop: 4,
  },
  actionButtons: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 16,
  },
  actionButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    borderRadius: 8,
    gap: 6,
  },
  actionButtonText: {
    fontSize: 14,
    fontWeight: '600',
  },
  modalOverlay: {
    flex: 1,
    justifyContent: 'flex-end',
  },
  modalContent: {
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    maxHeight: '60%',
    paddingTop: 16,
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingBottom: 12,
    borderBottomWidth: 1,
  },
  modalTitle: {
    fontSize: 18,
    fontWeight: '600',
  },
  modalBody: {
    paddingVertical: 8,
  },
  modalOption: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: 1,
    gap: 12,
  },
  modalOptionText: {
    fontSize: 15,
    flex: 1,
  },
});
