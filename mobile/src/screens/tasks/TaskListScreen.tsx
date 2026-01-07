import React, { useState, useEffect } from 'react';
import {
  View,
  FlatList,
  StyleSheet,
  TouchableOpacity,
  ActivityIndicator,
  RefreshControl,
  TextInput,
  Modal,
  ScrollView,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Search, XCircle, SlidersHorizontal, AlertCircle, Check, CheckCircle, Clock, Circle, CircleSlash, CircleCheckBig, Plus } from 'lucide-react-native';
import { useAppDispatch, useAppSelector } from '@store';
import {
  fetchTasks,
  completeTaskAsync,
  setFilters,
  clearFilters,
} from '@store/slices/tasksSlice';
import { getColors } from '@theme/colors';
import { StyledText } from '@components/StyledText';
import { Task } from '@types';

interface TaskListScreenProps {
  navigation: any;
  route: any;
}

interface FilterState {
  status?: string;
  priority?: string;
  dueDateRange?: 'today' | 'overdue' | 'week' | 'month' | 'all';
}

export default function TaskListScreen({ navigation, route }: TaskListScreenProps) {
  const insets = useSafeAreaInsets();
  const dispatch = useAppDispatch();
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  const { list, isLoading, error, filters, pagination } = useAppSelector(
    (state) => state.tasks
  );

  const [searchQuery, setSearchQuery] = useState('');
  const [showFilterModal, setShowFilterModal] = useState(false);
  const [localFilters, setLocalFilters] = useState<FilterState>(
    filters as FilterState
  );
  const [isRefreshing, setIsRefreshing] = useState(false);

  useEffect(() => {
    loadTasks();
  }, [filters]);

  const loadTasks = async () => {
    try {
      await dispatch(
        fetchTasks({
          page: 1,
          perPage: 20,
          ...filters,
        })
      ).unwrap();
    } catch (err) {
      console.error('Error loading tasks:', err);
    }
  };

  const handleRefresh = async () => {
    setIsRefreshing(true);
    try {
      await dispatch(
        fetchTasks({
          page: 1,
          perPage: 20,
          ...filters,
        })
      ).unwrap();
    } catch (err) {
      console.error('Error refreshing:', err);
    } finally {
      setIsRefreshing(false);
    }
  };

  const handleCompleteTask = async (taskId: string) => {
    try {
      await dispatch(completeTaskAsync(taskId)).unwrap();
    } catch (err) {
      console.error('Error completing task:', err);
    }
  };

  const applyFilters = () => {
    dispatch(setFilters(localFilters));
    setShowFilterModal(false);
  };

  const resetFilters = () => {
    setLocalFilters({});
    dispatch(clearFilters());
    setShowFilterModal(false);
  };

  const filteredTasks = searchQuery
    ? list.filter(
        (task) =>
          task.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
          (task.description?.toLowerCase().includes(searchQuery.toLowerCase()) ?? false)
      )
    : list;

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

  const formatDueDate = (dueDate?: string) => {
    if (!dueDate) return 'No due date';
    const date = new Date(dueDate);
    const today = new Date();
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);

    if (date.toDateString() === today.toDateString()) {
      return 'Today';
    }
    if (date.toDateString() === tomorrow.toDateString()) {
      return 'Tomorrow';
    }
    if (date < today) {
      return `${Math.floor(
        (today.getTime() - date.getTime()) / (1000 * 60 * 60 * 24)
      )}d overdue`;
    }
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  };

  const isTaskOverdue = (task: Task) => {
    if (!task.due_date || task.status === 'completed') return false;
    return new Date(task.due_date) < new Date();
  };

  const renderTaskCard = ({ item }: { item: Task }) => {
    const isOverdue = isTaskOverdue(item);

    return (
      <TouchableOpacity
        testID={`task-card-${item.id}`}
        onPress={() =>
          navigation.navigate('TaskDetail', { taskId: item.id })
        }
        style={[
          styles.taskCard,
          {
            backgroundColor: colors.surface,
            borderColor: isOverdue ? colors.error : colors.border,
            borderLeftColor: getPriorityColor(item.priority),
            borderLeftWidth: 4,
          },
        ]}
      >
        <View style={styles.cardHeader}>
          <View style={{ flex: 1 }}>
            <StyledText
              style={[
                styles.taskTitle,
                {
                  color: colors.text,
                  textDecorationLine: item.status === 'completed' ? 'line-through' : 'none',
                },
              ]}
              numberOfLines={2}
            >
              {item.title}
            </StyledText>
            {item.description && (
              <StyledText
                style={[styles.taskDescription, { color: colors.textSecondary }]}
                numberOfLines={1}
              >
                {item.description}
              </StyledText>
            )}
          </View>
          {item.status !== 'completed' && (
            <TouchableOpacity
              testID={`quick-complete-btn-${item.id}`}
              onPress={() => handleCompleteTask(item.id)}
              style={[styles.quickCompleteBtn, { backgroundColor: colors.primary }]}
            >
              <Check size={16} color="#fff" />
            </TouchableOpacity>
          )}
        </View>

        <View style={styles.cardFooter}>
          <View style={styles.badges}>
            {/* Status Badge */}
            <View
              style={[
                styles.badge,
                {
                  backgroundColor: getStatusColor(item.status),
                  opacity: 0.2,
                },
              ]}
            >
              {React.createElement(getStatusIcon(item.status), {
                size: 12,
                color: getStatusColor(item.status),
              })}
              <StyledText
                style={[
                  styles.badgeText,
                  { color: getStatusColor(item.status) },
                ]}
              >
                {item.status.replace('_', ' ')}
              </StyledText>
            </View>

            {/* Priority Badge */}
            <View
              style={[
                styles.badge,
                {
                  backgroundColor: getPriorityColor(item.priority),
                  opacity: 0.2,
                },
              ]}
            >
              <StyledText
                style={[
                  styles.badgeText,
                  { color: getPriorityColor(item.priority) },
                ]}
              >
                {item.priority}
              </StyledText>
            </View>

            {isOverdue && (
              <View
                style={[
                  styles.badge,
                  {
                    backgroundColor: colors.error,
                    opacity: 0.2,
                  },
                ]}
              >
                <StyledText style={[styles.badgeText, { color: colors.error }]}>
                  Overdue
                </StyledText>
              </View>
            )}
          </View>

          <StyledText
            style={[
              styles.dueDate,
              {
                color: isOverdue ? colors.error : colors.textSecondary,
              },
            ]}
          >
            {formatDueDate(item.due_date)}
          </StyledText>
        </View>

        {item.tags && item.tags.length > 0 && (
          <View style={styles.tagsContainer}>
            {item.tags.slice(0, 3).map((tag, index) => (
              <View
                key={index}
                style={[styles.tag, { backgroundColor: colors.primary, opacity: 0.15 }]}
              >
                <StyledText
                  style={[styles.tagText, { color: colors.primary }]}
                  numberOfLines={1}
                >
                  {tag}
                </StyledText>
              </View>
            ))}
            {item.tags.length > 3 && (
              <StyledText style={[styles.moreTagsText, { color: colors.textSecondary }]}>
                +{item.tags.length - 3}
              </StyledText>
            )}
          </View>
        )}
      </TouchableOpacity>
    );
  };

  const renderEmptyState = () => (
    <View style={[styles.emptyContainer, { paddingTop: insets.top + 100 }]}>
      <CircleCheckBig
        size={64}
        color={colors.textSecondary}
      />
      <StyledText style={[styles.emptyTitle, { color: colors.text }]}>
        No tasks yet
      </StyledText>
      <StyledText style={[styles.emptySubtitle, { color: colors.textSecondary }]}>
        Create your first task to get started
      </StyledText>
    </View>
  );

  if (isLoading && !isRefreshing) {
    return (
      <View style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      </View>
    );
  }

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      {/* Header */}
      <View style={[styles.header, { paddingTop: insets.top }]}>
        <View>
          <StyledText style={[styles.headerTitle, { color: colors.text }]}>
            Tasks
          </StyledText>
          <StyledText style={[styles.headerSubtitle, { color: colors.textSecondary }]}>
            {filteredTasks.length} task{filteredTasks.length !== 1 ? 's' : ''}
          </StyledText>
        </View>
      </View>

      {/* Search and Filter */}
      <View style={[styles.searchContainer, { backgroundColor: colors.surface }]}>
        <View
          style={[
            styles.searchInputContainer,
            { borderColor: colors.border, backgroundColor: colors.background },
          ]}
        >
          <Search
            size={20}
            color={colors.textSecondary}
          />
          <TextInput
            testID="task-search-input"
            style={[styles.searchInput, { color: colors.text }]}
            placeholder="Search tasks..."
            placeholderTextColor={colors.textSecondary}
            value={searchQuery}
            onChangeText={setSearchQuery}
          />
          {searchQuery !== '' && (
            <TouchableOpacity onPress={() => setSearchQuery('')}>
              <XCircle
                size={18}
                color={colors.textSecondary}
              />
            </TouchableOpacity>
          )}
        </View>

        <TouchableOpacity
          testID="task-filter-btn"
          onPress={() => setShowFilterModal(true)}
          style={[
            styles.filterButton,
            {
              backgroundColor: Object.keys(filters).length > 0 ? colors.primary : colors.surface,
              borderColor: colors.border,
            },
          ]}
        >
          <SlidersHorizontal
            size={20}
            color={
              Object.keys(filters).length > 0 ? '#fff' : colors.text
            }
          />
        </TouchableOpacity>
      </View>

      {/* Error State */}
      {error && (
        <View style={[styles.errorContainer, { backgroundColor: colors.error }]}>
          <AlertCircle size={20} color="#fff" />
          <StyledText style={[styles.errorText, { color: '#fff' }]}>
            {error}
          </StyledText>
          <TouchableOpacity onPress={loadTasks}>
            <StyledText style={[styles.retryText, { color: '#fff' }]}>
              Retry
            </StyledText>
          </TouchableOpacity>
        </View>
      )}

      {/* Task List */}
      <FlatList
        testID="tasks-list"
        data={filteredTasks}
        renderItem={renderTaskCard}
        keyExtractor={(item) => item.id}
        contentContainerStyle={[styles.listContent, { paddingBottom: insets.bottom + 80 }]}
        scrollIndicatorInsets={{ bottom: insets.bottom }}
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={handleRefresh}
            tintColor={colors.primary}
          />
        }
        ListEmptyComponent={!isLoading ? renderEmptyState : null}
      />

      {/* Filter Modal */}
      <Modal
        visible={showFilterModal}
        animationType="slide"
        transparent={true}
        onRequestClose={() => setShowFilterModal(false)}
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
                Filter Tasks
              </StyledText>
              <TouchableOpacity onPress={() => setShowFilterModal(false)}>
                <XCircle
                  size={24}
                  color={colors.text}
                />
              </TouchableOpacity>
            </View>

            <ScrollView
              style={styles.modalBody}
              showsVerticalScrollIndicator={false}
            >
              {/* Status Filter */}
              <View style={styles.filterGroup}>
                <StyledText style={[styles.filterLabel, { color: colors.text }]}>
                  Status
                </StyledText>
                <View style={styles.filterOptions}>
                  {['pending', 'in_progress', 'completed', 'cancelled'].map((status) => (
                    <TouchableOpacity
                      key={status}
                      testID={`status-filter-${status}`}
                      onPress={() =>
                        setLocalFilters({
                          ...localFilters,
                          status: localFilters.status === status ? undefined : status,
                        })
                      }
                      style={[
                        styles.filterOption,
                        {
                          backgroundColor:
                            localFilters.status === status
                              ? colors.primary
                              : colors.surface,
                          borderColor: colors.border,
                        },
                      ]}
                    >
                      <StyledText
                        style={[
                          styles.filterOptionText,
                          {
                            color:
                              localFilters.status === status
                                ? '#fff'
                                : colors.text,
                          },
                        ]}
                      >
                        {status.replace('_', ' ')}
                      </StyledText>
                    </TouchableOpacity>
                  ))}
                </View>
              </View>

              {/* Priority Filter */}
              <View style={styles.filterGroup}>
                <StyledText style={[styles.filterLabel, { color: colors.text }]}>
                  Priority
                </StyledText>
                <View style={styles.filterOptions}>
                  {['low', 'medium', 'high'].map((priority) => (
                    <TouchableOpacity
                      key={priority}
                      testID={`priority-filter-${priority}`}
                      onPress={() =>
                        setLocalFilters({
                          ...localFilters,
                          priority:
                            localFilters.priority === priority
                              ? undefined
                              : priority,
                        })
                      }
                      style={[
                        styles.filterOption,
                        {
                          backgroundColor:
                            localFilters.priority === priority
                              ? colors.primary
                              : colors.surface,
                          borderColor: colors.border,
                        },
                      ]}
                    >
                      <StyledText
                        style={[
                          styles.filterOptionText,
                          {
                            color:
                              localFilters.priority === priority
                                ? '#fff'
                                : colors.text,
                          },
                        ]}
                      >
                        {priority}
                      </StyledText>
                    </TouchableOpacity>
                  ))}
                </View>
              </View>

              {/* Due Date Filter */}
              <View style={styles.filterGroup}>
                <StyledText style={[styles.filterLabel, { color: colors.text }]}>
                  Due Date Range
                </StyledText>
                <View style={styles.filterOptions}>
                  {[
                    { key: 'today', label: 'Today' },
                    { key: 'overdue', label: 'Overdue' },
                    { key: 'week', label: 'This Week' },
                    { key: 'month', label: 'This Month' },
                    { key: 'all', label: 'All' },
                  ].map(({ key, label }) => (
                    <TouchableOpacity
                      key={key}
                      testID={`duedate-filter-${key}`}
                      onPress={() =>
                        setLocalFilters({
                          ...localFilters,
                          dueDateRange:
                            localFilters.dueDateRange === key
                              ? undefined
                              : (key as any),
                        })
                      }
                      style={[
                        styles.filterOption,
                        {
                          backgroundColor:
                            localFilters.dueDateRange === key
                              ? colors.primary
                              : colors.surface,
                          borderColor: colors.border,
                        },
                      ]}
                    >
                      <StyledText
                        style={[
                          styles.filterOptionText,
                          {
                            color:
                              localFilters.dueDateRange === key
                                ? '#fff'
                                : colors.text,
                          },
                        ]}
                      >
                        {label}
                      </StyledText>
                    </TouchableOpacity>
                  ))}
                </View>
              </View>
            </ScrollView>

            <View
              style={[
                styles.modalFooter,
                { borderTopColor: colors.border },
              ]}
            >
              <TouchableOpacity
                testID="reset-filter-btn"
                onPress={resetFilters}
                style={[styles.footerButton, { backgroundColor: colors.surface }]}
              >
                <StyledText style={[styles.footerButtonText, { color: colors.text }]}>
                  Reset
                </StyledText>
              </TouchableOpacity>
              <TouchableOpacity
                testID="apply-filter-btn"
                onPress={applyFilters}
                style={[styles.footerButton, { backgroundColor: colors.primary }]}
              >
                <StyledText style={[styles.footerButtonText, { color: '#fff' }]}>
                  Apply
                </StyledText>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>

      {/* FAB - Create Task */}
      <TouchableOpacity
        testID="create-task-fab"
        onPress={() => navigation.navigate('TaskEdit', { mode: 'create' })}
        style={[
          styles.fab,
          {
            backgroundColor: colors.primary,
            bottom: insets.bottom + 16,
          },
        ]}
      >
        <Plus size={28} color="#fff" />
      </TouchableOpacity>
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
  header: {
    paddingHorizontal: 16,
    paddingBottom: 16,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: '700',
    marginBottom: 4,
  },
  headerSubtitle: {
    fontSize: 14,
  },
  searchContainer: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    flexDirection: 'row',
    gap: 8,
  },
  searchInputContainer: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    borderRadius: 8,
    borderWidth: 1,
    gap: 8,
  },
  searchInput: {
    flex: 1,
    paddingVertical: 10,
    fontSize: 14,
  },
  filterButton: {
    width: 44,
    height: 44,
    borderRadius: 8,
    borderWidth: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  errorContainer: {
    marginHorizontal: 16,
    marginTop: 8,
    marginBottom: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderRadius: 8,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  errorText: {
    flex: 1,
    fontSize: 13,
    fontWeight: '500',
  },
  retryText: {
    fontSize: 12,
    fontWeight: '600',
    textDecorationLine: 'underline',
  },
  listContent: {
    paddingHorizontal: 16,
    paddingTop: 8,
  },
  taskCard: {
    borderRadius: 8,
    borderWidth: 1,
    padding: 12,
    marginBottom: 12,
  },
  cardHeader: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 8,
  },
  taskTitle: {
    fontSize: 15,
    fontWeight: '600',
    marginBottom: 2,
  },
  taskDescription: {
    fontSize: 13,
  },
  quickCompleteBtn: {
    width: 32,
    height: 32,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
  },
  cardFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 8,
  },
  badges: {
    flexDirection: 'row',
    gap: 6,
    flex: 1,
    flexWrap: 'wrap',
  },
  badge: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
    gap: 4,
  },
  badgeText: {
    fontSize: 11,
    fontWeight: '500',
  },
  dueDate: {
    fontSize: 12,
    fontWeight: '500',
  },
  tagsContainer: {
    flexDirection: 'row',
    gap: 6,
    flexWrap: 'wrap',
  },
  tag: {
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
  },
  tagText: {
    fontSize: 11,
    fontWeight: '500',
  },
  moreTagsText: {
    fontSize: 11,
    fontWeight: '500',
    marginTop: 4,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginTop: 16,
    marginBottom: 8,
  },
  emptySubtitle: {
    fontSize: 14,
    textAlign: 'center',
  },
  fab: {
    position: 'absolute',
    bottom: 16,
    right: 16,
    width: 56,
    height: 56,
    borderRadius: 28,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 8,
  },
  modalOverlay: {
    flex: 1,
    justifyContent: 'flex-end',
  },
  modalContent: {
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    maxHeight: '80%',
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
    paddingHorizontal: 16,
    paddingVertical: 16,
  },
  filterGroup: {
    marginBottom: 24,
  },
  filterLabel: {
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 8,
  },
  filterOptions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  filterOption: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 6,
    borderWidth: 1,
  },
  filterOptionText: {
    fontSize: 13,
    fontWeight: '500',
  },
  modalFooter: {
    flexDirection: 'row',
    gap: 12,
    paddingHorizontal: 16,
    paddingVertical: 16,
    borderTopWidth: 1,
  },
  footerButton: {
    flex: 1,
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
  },
  footerButtonText: {
    fontSize: 14,
    fontWeight: '600',
  },
});
