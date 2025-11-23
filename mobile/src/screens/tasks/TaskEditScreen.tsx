import React, { useState, useEffect } from 'react';
import {
  View,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  ActivityIndicator,
  Alert,
  Modal,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import DateTimePicker from '@react-native-community/datetimepicker';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useAppDispatch, useAppSelector } from '@store';
import {
  createTask,
  updateTaskAsync,
  fetchTaskDetail,
} from '@store/slices/tasksSlice';
import { getColors } from '@theme/colors';
import { StyledText } from '@components/StyledText';
import { Task } from '@types';

interface TaskEditScreenProps {
  navigation: any;
  route: any;
}

interface FormData {
  title: string;
  description: string;
  priority: 'low' | 'medium' | 'high';
  status: 'pending' | 'in_progress' | 'completed' | 'cancelled';
  dueDate?: Date;
  assignedTo?: string;
  relatedEntity?: {
    type: 'campaign' | 'contact' | 'landing_page' | 'general';
    id?: string;
  };
  tags: string[];
}

interface FormErrors {
  title?: string;
  description?: string;
  [key: string]: string | undefined;
}

export default function TaskEditScreen({ navigation, route }: TaskEditScreenProps) {
  const insets = useSafeAreaInsets();
  const dispatch = useAppDispatch();
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  const { mode = 'create', taskId } = route.params || {};
  const { current: existingTask, isLoading: tasksLoading } = useAppSelector(
    (state) => state.tasks
  );

  const [formData, setFormData] = useState<FormData>({
    title: '',
    description: '',
    priority: 'medium',
    status: 'pending',
    tags: [],
  });

  const [errors, setErrors] = useState<FormErrors>({});
  const [isSaving, setIsSaving] = useState(false);
  const [showDatePicker, setShowDatePicker] = useState(false);
  const [showPriorityModal, setShowPriorityModal] = useState(false);
  const [showStatusModal, setShowStatusModal] = useState(false);
  const [showEntityModal, setShowEntityModal] = useState(false);
  const [tagInput, setTagInput] = useState('');

  useEffect(() => {
    if (mode === 'edit' && taskId && !existingTask) {
      dispatch(fetchTaskDetail(taskId));
    }
  }, [mode, taskId, existingTask]);

  useEffect(() => {
    if (mode === 'edit' && existingTask) {
      setFormData({
        title: existingTask.title,
        description: existingTask.description || '',
        priority: existingTask.priority,
        status: existingTask.status,
        dueDate: existingTask.due_date ? new Date(existingTask.due_date) : undefined,
        assignedTo: existingTask.assigned_to,
        relatedEntity: existingTask.related_entity,
        tags: existingTask.tags || [],
      });
    }
  }, [mode, existingTask]);

  const validateForm = (): boolean => {
    const newErrors: FormErrors = {};

    if (!formData.title.trim()) {
      newErrors.title = 'Title is required';
    }
    if (formData.title.length > 200) {
      newErrors.title = 'Title must be less than 200 characters';
    }
    if (formData.description.length > 1000) {
      newErrors.description = 'Description must be less than 1000 characters';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSave = async () => {
    if (!validateForm()) return;

    setIsSaving(true);
    try {
      const payload = {
        title: formData.title.trim(),
        description: formData.description.trim() || undefined,
        priority: formData.priority,
        status: formData.status,
        due_date: formData.dueDate?.toISOString(),
        assigned_to: formData.assignedTo,
        related_entity: formData.relatedEntity,
        tags: formData.tags,
      };

      if (mode === 'create') {
        await dispatch(createTask(payload)).unwrap();
        Alert.alert('Success', 'Task created successfully');
        navigation.goBack();
      } else if (mode === 'edit' && existingTask) {
        await dispatch(
          updateTaskAsync({
            id: existingTask.id,
            data: payload,
          })
        ).unwrap();
        Alert.alert('Success', 'Task updated successfully');
        navigation.goBack();
      }
    } catch (error: any) {
      Alert.alert('Error', error.message || 'Failed to save task');
      console.error('Error saving task:', error);
    } finally {
      setIsSaving(false);
    }
  };

  const handleDateChange = (event: any, selectedDate?: Date) => {
    if (event.type === 'dismissed') {
      setShowDatePicker(false);
      return;
    }

    if (selectedDate) {
      setFormData({ ...formData, dueDate: selectedDate });
    }
    setShowDatePicker(false);
  };

  const handleAddTag = () => {
    if (tagInput.trim() && formData.tags.length < 10) {
      if (!formData.tags.includes(tagInput.trim())) {
        setFormData({
          ...formData,
          tags: [...formData.tags, tagInput.trim()],
        });
      }
      setTagInput('');
    }
  };

  const handleRemoveTag = (tagToRemove: string) => {
    setFormData({
      ...formData,
      tags: formData.tags.filter((tag) => tag !== tagToRemove),
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
        return 'check-circle';
      case 'in_progress':
        return 'progress-clock';
      case 'pending':
        return 'circle-outline';
      case 'cancelled':
        return 'close-circle';
      default:
        return 'circle-outline';
    }
  };

  if (mode === 'edit' && tasksLoading && !existingTask) {
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
        <TouchableOpacity onPress={() => navigation.goBack()}>
          <MaterialCommunityIcons
            name="arrow-left"
            size={24}
            color={colors.text}
          />
        </TouchableOpacity>
        <StyledText style={[styles.headerTitle, { color: colors.text }]}>
          {mode === 'create' ? 'New Task' : 'Edit Task'}
        </StyledText>
        <View style={{ width: 24 }} />
      </View>

      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
      >
        {/* Title Field */}
        <View style={styles.formGroup}>
          <StyledText style={[styles.label, { color: colors.text }]}>
            Title *
          </StyledText>
          <TextInput
            testID="task-title-input"
            style={[
              styles.input,
              {
                backgroundColor: colors.surface,
                borderColor: errors.title ? colors.error : colors.border,
                color: colors.text,
              },
            ]}
            placeholder="What needs to be done?"
            placeholderTextColor={colors.textSecondary}
            value={formData.title}
            onChangeText={(text) => {
              setFormData({ ...formData, title: text });
              if (errors.title) setErrors({ ...errors, title: undefined });
            }}
            editable={!isSaving}
            maxLength={200}
          />
          {errors.title && (
            <StyledText style={[styles.errorText, { color: colors.error }]}>
              {errors.title}
            </StyledText>
          )}
          <StyledText style={[styles.charCount, { color: colors.textSecondary }]}>
            {formData.title.length}/200
          </StyledText>
        </View>

        {/* Description Field */}
        <View style={styles.formGroup}>
          <StyledText style={[styles.label, { color: colors.text }]}>
            Description
          </StyledText>
          <TextInput
            testID="task-description-input"
            style={[
              styles.textArea,
              {
                backgroundColor: colors.surface,
                borderColor: errors.description ? colors.error : colors.border,
                color: colors.text,
              },
            ]}
            placeholder="Add more details..."
            placeholderTextColor={colors.textSecondary}
            value={formData.description}
            onChangeText={(text) => {
              setFormData({ ...formData, description: text });
              if (errors.description) setErrors({ ...errors, description: undefined });
            }}
            multiline
            numberOfLines={4}
            editable={!isSaving}
            maxLength={1000}
          />
          {errors.description && (
            <StyledText style={[styles.errorText, { color: colors.error }]}>
              {errors.description}
            </StyledText>
          )}
          <StyledText style={[styles.charCount, { color: colors.textSecondary }]}>
            {formData.description.length}/1000
          </StyledText>
        </View>

        {/* Priority Selector */}
        <View style={styles.formGroup}>
          <StyledText style={[styles.label, { color: colors.text }]}>
            Priority
          </StyledText>
          <TouchableOpacity
            testID="priority-selector"
            disabled={isSaving}
            onPress={() => setShowPriorityModal(true)}
            style={[
              styles.selectorButton,
              {
                backgroundColor: colors.surface,
                borderColor: colors.border,
              },
            ]}
          >
            <View
              style={[
                styles.priorityIndicator,
                { backgroundColor: getPriorityColor(formData.priority) },
              ]}
            />
            <StyledText style={[styles.selectorText, { color: colors.text }]}>
              {formData.priority}
            </StyledText>
            <MaterialCommunityIcons
              name="chevron-down"
              size={20}
              color={colors.textSecondary}
            />
          </TouchableOpacity>
        </View>

        {/* Status Selector */}
        <View style={styles.formGroup}>
          <StyledText style={[styles.label, { color: colors.text }]}>
            Status
          </StyledText>
          <TouchableOpacity
            testID="status-selector"
            disabled={isSaving}
            onPress={() => setShowStatusModal(true)}
            style={[
              styles.selectorButton,
              {
                backgroundColor: colors.surface,
                borderColor: colors.border,
              },
            ]}
          >
            <MaterialCommunityIcons
              name={getStatusIcon(formData.status)}
              size={20}
              color={getStatusColor(formData.status)}
            />
            <StyledText style={[styles.selectorText, { color: colors.text }]}>
              {formData.status.replace('_', ' ')}
            </StyledText>
            <MaterialCommunityIcons
              name="chevron-down"
              size={20}
              color={colors.textSecondary}
            />
          </TouchableOpacity>
        </View>

        {/* Due Date Picker */}
        <View style={styles.formGroup}>
          <StyledText style={[styles.label, { color: colors.text }]}>
            Due Date
          </StyledText>
          <TouchableOpacity
            testID="due-date-picker"
            disabled={isSaving}
            onPress={() => setShowDatePicker(true)}
            style={[
              styles.selectorButton,
              {
                backgroundColor: colors.surface,
                borderColor: colors.border,
              },
            ]}
          >
            <MaterialCommunityIcons
              name="calendar"
              size={20}
              color={colors.primary}
            />
            <StyledText style={[styles.selectorText, { color: colors.text }]}>
              {formData.dueDate
                ? formData.dueDate.toLocaleDateString('en-US', {
                    month: 'short',
                    day: 'numeric',
                    year: 'numeric',
                  })
                : 'Select due date'}
            </StyledText>
            {formData.dueDate && (
              <TouchableOpacity
                onPress={() => setFormData({ ...formData, dueDate: undefined })}
              >
                <MaterialCommunityIcons
                  name="close"
                  size={18}
                  color={colors.textSecondary}
                />
              </TouchableOpacity>
            )}
          </TouchableOpacity>
        </View>

        {showDatePicker && (
          <DateTimePicker
            value={formData.dueDate || new Date()}
            mode="date"
            display="spinner"
            onChange={handleDateChange}
            minimumDate={new Date()}
          />
        )}

        {/* Tags Input */}
        <View style={styles.formGroup}>
          <StyledText style={[styles.label, { color: colors.text }]}>
            Tags
          </StyledText>
          <View
            style={[
              styles.tagInputContainer,
              {
                backgroundColor: colors.surface,
                borderColor: colors.border,
              },
            ]}
          >
            <TextInput
              testID="tag-input"
              style={[styles.tagInput, { color: colors.text }]}
              placeholder="Add a tag and press enter"
              placeholderTextColor={colors.textSecondary}
              value={tagInput}
              onChangeText={setTagInput}
              onSubmitEditing={handleAddTag}
              editable={!isSaving && formData.tags.length < 10}
            />
            <TouchableOpacity
              onPress={handleAddTag}
              disabled={isSaving || formData.tags.length >= 10}
            >
              <MaterialCommunityIcons
                name="plus-circle"
                size={20}
                color={formData.tags.length >= 10 ? colors.textSecondary : colors.primary}
              />
            </TouchableOpacity>
          </View>
          <View style={styles.tagsContainer}>
            {formData.tags.map((tag, index) => (
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
                <TouchableOpacity
                  onPress={() => handleRemoveTag(tag)}
                  disabled={isSaving}
                >
                  <MaterialCommunityIcons
                    name="close"
                    size={14}
                    color={colors.primary}
                  />
                </TouchableOpacity>
              </View>
            ))}
          </View>
          <StyledText style={[styles.helperText, { color: colors.textSecondary }]}>
            {formData.tags.length}/10 tags
          </StyledText>
        </View>

        {/* Action Buttons */}
        <View style={styles.actionButtons}>
          <TouchableOpacity
            onPress={() => navigation.goBack()}
            disabled={isSaving}
            style={[
              styles.button,
              { backgroundColor: colors.surface, borderColor: colors.border, borderWidth: 1 },
            ]}
          >
            <StyledText style={[styles.buttonText, { color: colors.text }]}>
              Cancel
            </StyledText>
          </TouchableOpacity>

          <TouchableOpacity
            onPress={handleSave}
            disabled={isSaving}
            style={[
              styles.button,
              {
                backgroundColor: isSaving ? colors.textSecondary : colors.primary,
              },
            ]}
          >
            {isSaving ? (
              <ActivityIndicator color="#fff" size="small" />
            ) : (
              <StyledText style={[styles.buttonText, { color: '#fff' }]}>
                {mode === 'create' ? 'Create Task' : 'Update Task'}
              </StyledText>
            )}
          </TouchableOpacity>
        </View>

        <View style={{ height: insets.bottom + 32 }} />
      </ScrollView>

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
                Select Priority
              </StyledText>
              <TouchableOpacity onPress={() => setShowPriorityModal(false)}>
                <MaterialCommunityIcons
                  name="close"
                  size={24}
                  color={colors.text}
                />
              </TouchableOpacity>
            </View>

            <View style={styles.modalBody}>
              {(['low', 'medium', 'high'] as const).map((priority) => (
                <TouchableOpacity
                  key={priority}
                  testID={`priority-modal-${priority}`}
                  onPress={() => {
                    setFormData({ ...formData, priority });
                    setShowPriorityModal(false);
                  }}
                  style={[
                    styles.modalOption,
                    {
                      backgroundColor:
                        formData.priority === priority
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
                          formData.priority === priority ? '600' : '400',
                      },
                    ]}
                  >
                    {priority}
                  </StyledText>
                  {formData.priority === priority && (
                    <MaterialCommunityIcons
                      name="check"
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
                Select Status
              </StyledText>
              <TouchableOpacity onPress={() => setShowStatusModal(false)}>
                <MaterialCommunityIcons
                  name="close"
                  size={24}
                  color={colors.text}
                />
              </TouchableOpacity>
            </View>

            <View style={styles.modalBody}>
              {(
                [
                  'pending',
                  'in_progress',
                  'completed',
                  'cancelled',
                ] as const
              ).map((status) => (
                <TouchableOpacity
                  key={status}
                  testID={`status-modal-${status}`}
                  onPress={() => {
                    setFormData({ ...formData, status });
                    setShowStatusModal(false);
                  }}
                  style={[
                    styles.modalOption,
                    {
                      backgroundColor:
                        formData.status === status
                          ? getStatusColor(status) + '20'
                          : 'transparent',
                      borderBottomColor: colors.border,
                    },
                  ]}
                >
                  <MaterialCommunityIcons
                    name={getStatusIcon(status)}
                    size={20}
                    color={getStatusColor(status)}
                  />
                  <StyledText
                    style={[
                      styles.modalOptionText,
                      {
                        color: colors.text,
                        fontWeight:
                          formData.status === status ? '600' : '400',
                      },
                    ]}
                  >
                    {status.replace('_', ' ')}
                  </StyledText>
                  {formData.status === status && (
                    <MaterialCommunityIcons
                      name="check"
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
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingBottom: 16,
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: '600',
  },
  content: {
    paddingHorizontal: 16,
    paddingVertical: 12,
    paddingBottom: 32,
  },
  formGroup: {
    marginBottom: 20,
  },
  label: {
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 8,
  },
  input: {
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 14,
    marginBottom: 4,
  },
  textArea: {
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 14,
    marginBottom: 4,
    textAlignVertical: 'top',
  },
  charCount: {
    fontSize: 12,
    textAlign: 'right',
  },
  errorText: {
    fontSize: 12,
    fontWeight: '500',
    marginTop: 4,
  },
  selectorButton: {
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  priorityIndicator: {
    width: 12,
    height: 12,
    borderRadius: 6,
  },
  selectorText: {
    fontSize: 14,
    fontWeight: '500',
    flex: 1,
  },
  tagInputContainer: {
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 8,
  },
  tagInput: {
    flex: 1,
    fontSize: 14,
  },
  tagsContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
    marginBottom: 4,
  },
  tag: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 6,
    borderRadius: 4,
    gap: 4,
  },
  tagText: {
    fontSize: 12,
    fontWeight: '500',
  },
  helperText: {
    fontSize: 12,
    textAlign: 'right',
  },
  actionButtons: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 24,
  },
  button: {
    flex: 1,
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  buttonText: {
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
