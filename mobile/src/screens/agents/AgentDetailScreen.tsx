import React, { useEffect, useState } from 'react';
import {
  View,
  ScrollView,
  Text,
  StyleSheet,
  TouchableOpacity,
  TextInput,
  ActivityIndicator,
  Alert,
  SafeAreaView,
  Modal,
} from 'react-native';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAppDispatch, useAppSelector } from '@store';
import { fetchAgentDetail, executeAgentAsync, clearExecution, clearCurrentAgent } from '@store/slices/agentsSlice';
import { AgentField } from '@types';
import { getColors } from '@theme/colors';

interface AgentDetailScreenProps {
  navigation: any;
  route: any;
}

interface FormValues {
  [key: string]: string;
}

export default function AgentDetailScreen({ navigation, route }: AgentDetailScreenProps) {
  const dispatch = useAppDispatch();
  const { agentId } = route.params;
  const { current: agent, isLoading, error, execution } = useAppSelector(
    (state) => state.agents
  );
  const { theme } = useAppSelector((state) => state.ui);
  const colors = getColors(theme);

  const [formValues, setFormValues] = useState<FormValues>({});
  const [isExecuting, setIsExecuting] = useState(false);
  const [showResultModal, setShowResultModal] = useState(false);
  const [validationErrors, setValidationErrors] = useState<{ [key: string]: string }>({});

  useFocusEffect(
    React.useCallback(() => {
      dispatch(fetchAgentDetail(agentId));
      return () => {
        dispatch(clearCurrentAgent());
      };
    }, [agentId])
  );

  // Initialize form values from agent fields
  useEffect(() => {
    if (agent?.fields) {
      const initialValues: FormValues = {};
      agent.fields.forEach((field: AgentField) => {
        initialValues[field.name] = '';
      });
      setFormValues(initialValues);
    }
  }, [agent]);

  // Show result modal when execution completes
  useEffect(() => {
    if (execution) {
      setShowResultModal(true);
    }
  }, [execution]);

  const getIconForAgent = (agentType: string) => {
    const iconMap: Record<string, string> = {
      content_generator: 'file-document-plus',
      data_processor: 'chart-line',
      api_integration: 'api',
      workflow_automation: 'workflow',
      custom: 'robot',
    };
    return iconMap[agentType] || 'robot';
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

  const validateForm = (): boolean => {
    const errors: { [key: string]: string } = {};

    if (agent?.fields) {
      agent.fields.forEach((field: AgentField) => {
        if (field.required && !formValues[field.name]?.trim()) {
          errors[field.name] = `${field.name} is required`;
        }
      });
    }

    setValidationErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const handleExecute = async () => {
    if (!validateForm()) {
      Alert.alert('Validation Error', 'Please fill in all required fields');
      return;
    }

    setIsExecuting(true);
    try {
      const mainTask = formValues[agent?.fields?.[0]?.name] || '';
      await dispatch(
        executeAgentAsync({
          agentId,
          request: {
            task: mainTask,
            context: formValues,
          },
        })
      ).unwrap();
    } catch (error: any) {
      Alert.alert('Error', error.message || 'Failed to execute agent');
      console.error('Error executing agent:', error);
    } finally {
      setIsExecuting(false);
    }
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'pending':
        return colors.warning;
      case 'processing':
        return colors.info;
      case 'completed':
        return colors.success;
      case 'failed':
        return colors.error;
      default:
        return colors.textSecondary;
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'pending':
        return 'clock-outline';
      case 'processing':
        return 'loading';
      case 'completed':
        return 'check-circle';
      case 'failed':
        return 'alert-circle';
      default:
        return 'help-circle';
    }
  };

  if (isLoading) {
    return (
      <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      </SafeAreaView>
    );
  }

  if (error || !agent) {
    return (
      <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
        <View style={styles.centerContainer}>
          <MaterialCommunityIcons name="alert-circle" size={64} color={colors.error} />
          <Text style={[styles.errorText, { color: colors.error }]}>
            Failed to load agent
          </Text>
          <TouchableOpacity
            style={[styles.retryButton, { backgroundColor: colors.primary }]}
            onPress={() => dispatch(fetchAgentDetail(agentId))}
          >
            <Text style={styles.retryButtonText}>Retry</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: colors.background }]}>
      <ScrollView contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        {/* Agent Header */}
        <View style={[styles.headerCard, { backgroundColor: colors.card, borderColor: colors.border }]}>
          <View
            style={[styles.agentIconContainer, { backgroundColor: colors.primary + '20' }]}
          >
            <MaterialCommunityIcons
              name={getIconForAgent(agent.agent_type) as any}
              size={40}
              color={colors.primary}
            />
          </View>
          <Text style={[styles.agentName, { color: colors.text }]}>{agent.name}</Text>
          <Text style={[styles.agentType, { color: colors.textSecondary }]}>
            {getLabelForAgentType(agent.agent_type)}
          </Text>
          {agent.description && (
            <Text style={[styles.agentDescription, { color: colors.textSecondary }]}>
              {agent.description}
            </Text>
          )}
        </View>

        {/* Agent Fields Form */}
        {agent.fields && agent.fields.length > 0 && (
          <View>
            <Text style={[styles.sectionTitle, { color: colors.text }]}>
              Input Details
            </Text>
            {agent.fields.map((field: AgentField, index: number) => (
              <View key={`${field.name}-${index}`} style={styles.fieldContainer}>
                <Text style={[styles.fieldLabel, { color: colors.text }]}>
                  {field.question}
                  {field.required && <Text style={[styles.requiredMark, { color: colors.error }]}>*</Text>}
                </Text>
                {field.type === 'textarea' ? (
                  <TextInput
                    style={[
                      styles.textAreaInput,
                      {
                        borderColor: validationErrors[field.name] ? colors.error : colors.border,
                        color: colors.text,
                        backgroundColor: colors.inputBackground,
                      },
                    ]}
                    placeholder={field.examples?.[0] || `Enter ${field.name}`}
                    placeholderTextColor={colors.textSecondary}
                    value={formValues[field.name] || ''}
                    onChangeText={(text) => {
                      setFormValues({ ...formValues, [field.name]: text });
                      if (validationErrors[field.name]) {
                        setValidationErrors({
                          ...validationErrors,
                          [field.name]: undefined,
                        });
                      }
                    }}
                    multiline
                    numberOfLines={4}
                    editable={!isExecuting}
                  />
                ) : field.type === 'select' && field.options ? (
                  <TouchableOpacity
                    style={[
                      styles.selectInput,
                      {
                        borderColor: validationErrors[field.name] ? colors.error : colors.border,
                        backgroundColor: colors.inputBackground,
                      },
                    ]}
                  >
                    <Text
                      style={[
                        styles.selectText,
                        {
                          color: formValues[field.name] ? colors.text : colors.textSecondary,
                        },
                      ]}
                    >
                      {formValues[field.name] || `Select ${field.name}`}
                    </Text>
                  </TouchableOpacity>
                ) : (
                  <TextInput
                    style={[
                      styles.textInput,
                      {
                        borderColor: validationErrors[field.name] ? colors.error : colors.border,
                        color: colors.text,
                        backgroundColor: colors.inputBackground,
                      },
                    ]}
                    placeholder={field.examples?.[0] || `Enter ${field.name}`}
                    placeholderTextColor={colors.textSecondary}
                    value={formValues[field.name] || ''}
                    onChangeText={(text) => {
                      setFormValues({ ...formValues, [field.name]: text });
                      if (validationErrors[field.name]) {
                        setValidationErrors({
                          ...validationErrors,
                          [field.name]: undefined,
                        });
                      }
                    }}
                    editable={!isExecuting}
                  />
                )}
                {validationErrors[field.name] && (
                  <Text style={[styles.errorMessage, { color: colors.error }]}>
                    {validationErrors[field.name]}
                  </Text>
                )}
                {field.examples && field.examples.length > 0 && (
                  <Text style={[styles.exampleText, { color: colors.textSecondary }]}>
                    Example: {field.examples[0]}
                  </Text>
                )}
              </View>
            ))}
          </View>
        )}

        {/* Capabilities Section */}
        {agent.capabilities && agent.capabilities.length > 0 && (
          <View>
            <Text style={[styles.sectionTitle, { color: colors.text }]}>
              Capabilities
            </Text>
            {agent.capabilities.map((capability: string, index: number) => (
              <View
                key={`${capability}-${index}`}
                style={[styles.capabilityItem, { borderColor: colors.border }]}
              >
                <MaterialCommunityIcons
                  name="check-circle"
                  size={18}
                  color={colors.success}
                  style={styles.capabilityIcon}
                />
                <Text style={[styles.capabilityText, { color: colors.text }]}>
                  {capability}
                </Text>
              </View>
            ))}
          </View>
        )}

        {/* Execute Button */}
        <TouchableOpacity
          style={[
            styles.executeButton,
            { backgroundColor: colors.primary },
            isExecuting && { opacity: 0.6 },
          ]}
          onPress={handleExecute}
          disabled={isExecuting}
        >
          {isExecuting ? (
            <>
              <ActivityIndicator size="small" color="white" style={styles.buttonLoader} />
              <Text style={styles.executeButtonText}>Executing...</Text>
            </>
          ) : (
            <>
              <MaterialCommunityIcons name="play-circle" size={20} color="white" />
              <Text style={styles.executeButtonText}>Execute Agent</Text>
            </>
          )}
        </TouchableOpacity>
      </ScrollView>

      {/* Result Modal */}
      <Modal
        visible={showResultModal}
        transparent
        animationType="slide"
        onRequestClose={() => {
          setShowResultModal(false);
          dispatch(clearExecution());
        }}
      >
        <SafeAreaView style={[styles.modalContainer, { backgroundColor: colors.background }]}>
          <View style={styles.modalHeader}>
            <Text style={[styles.modalTitle, { color: colors.text }]}>
              Execution Result
            </Text>
            <TouchableOpacity
              onPress={() => {
                setShowResultModal(false);
                dispatch(clearExecution());
              }}
            >
              <MaterialCommunityIcons name="close" size={24} color={colors.text} />
            </TouchableOpacity>
          </View>

          <ScrollView contentContainerStyle={styles.modalContent}>
            {execution && (
              <View>
                {/* Status Card */}
                <View style={[styles.statusCard, { backgroundColor: colors.card, borderColor: colors.border }]}>
                  <View style={styles.statusRow}>
                    <MaterialCommunityIcons
                      name={getStatusIcon(execution.status) as any}
                      size={32}
                      color={getStatusColor(execution.status)}
                    />
                    <View style={styles.statusInfo}>
                      <Text style={[styles.statusLabel, { color: colors.textSecondary }]}>
                        Status
                      </Text>
                      <Text
                        style={[
                          styles.statusValue,
                          { color: getStatusColor(execution.status) },
                        ]}
                      >
                        {execution.status.toUpperCase()}
                      </Text>
                    </View>
                  </View>
                </View>

                {/* Job ID */}
                {execution.job_id && (
                  <View style={[styles.infoCard, { backgroundColor: colors.card, borderColor: colors.border }]}>
                    <Text style={[styles.infoLabel, { color: colors.textSecondary }]}>
                      Job ID
                    </Text>
                    <Text style={[styles.infoValue, { color: colors.text }]}>
                      {execution.job_id}
                    </Text>
                  </View>
                )}

                {/* Result */}
                {execution.result && (
                  <View style={[styles.infoCard, { backgroundColor: colors.card, borderColor: colors.border }]}>
                    <Text style={[styles.infoLabel, { color: colors.textSecondary }]}>
                      Result
                    </Text>
                    <Text style={[styles.infoValue, { color: colors.text }]}>
                      {typeof execution.result === 'string'
                        ? execution.result
                        : JSON.stringify(execution.result, null, 2)}
                    </Text>
                  </View>
                )}

                {/* Error */}
                {execution.error && (
                  <View
                    style={[
                      styles.infoCard,
                      { backgroundColor: colors.error + '20', borderColor: colors.error },
                    ]}
                  >
                    <Text style={[styles.infoLabel, { color: colors.error }]}>
                      Error
                    </Text>
                    <Text style={[styles.infoValue, { color: colors.error }]}>
                      {execution.error}
                    </Text>
                  </View>
                )}
              </View>
            )}
          </ScrollView>

          <TouchableOpacity
            style={[styles.closeButton, { backgroundColor: colors.primary }]}
            onPress={() => {
              setShowResultModal(false);
              dispatch(clearExecution());
            }}
          >
            <Text style={styles.closeButtonText}>Close</Text>
          </TouchableOpacity>
        </SafeAreaView>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  scrollContent: {
    padding: 16,
    paddingBottom: 24,
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  headerCard: {
    borderRadius: 12,
    borderWidth: 1,
    padding: 20,
    alignItems: 'center',
    marginBottom: 24,
  },
  agentIconContainer: {
    width: 60,
    height: 60,
    borderRadius: 12,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 12,
  },
  agentName: {
    fontSize: 20,
    fontWeight: '700',
    marginBottom: 4,
    textAlign: 'center',
  },
  agentType: {
    fontSize: 13,
    marginBottom: 12,
  },
  agentDescription: {
    fontSize: 14,
    lineHeight: 20,
    textAlign: 'center',
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginTop: 16,
    marginBottom: 12,
  },
  fieldContainer: {
    marginBottom: 16,
  },
  fieldLabel: {
    fontSize: 14,
    fontWeight: '500',
    marginBottom: 6,
  },
  requiredMark: {
    marginLeft: 2,
  },
  textInput: {
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 14,
  },
  textAreaInput: {
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    fontSize: 14,
    textAlignVertical: 'top',
  },
  selectInput: {
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    justifyContent: 'center',
  },
  selectText: {
    fontSize: 14,
  },
  errorMessage: {
    fontSize: 12,
    marginTop: 4,
  },
  exampleText: {
    fontSize: 12,
    marginTop: 4,
    fontStyle: 'italic',
  },
  capabilityItem: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    marginBottom: 8,
  },
  capabilityIcon: {
    marginRight: 10,
  },
  capabilityText: {
    fontSize: 14,
    flex: 1,
  },
  executeButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 12,
    borderRadius: 8,
    marginTop: 24,
    gap: 8,
  },
  buttonLoader: {
    marginRight: 4,
  },
  executeButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
  retryButton: {
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 8,
    marginTop: 16,
  },
  retryButtonText: {
    color: 'white',
    fontSize: 14,
    fontWeight: '600',
    textAlign: 'center',
  },
  errorText: {
    fontSize: 16,
    fontWeight: '600',
    marginTop: 16,
    textAlign: 'center',
  },
  modalContainer: {
    flex: 1,
  },
  modalHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
  },
  modalTitle: {
    fontSize: 18,
    fontWeight: '600',
  },
  modalContent: {
    padding: 16,
    paddingBottom: 24,
  },
  statusCard: {
    borderRadius: 12,
    borderWidth: 1,
    padding: 16,
    marginBottom: 16,
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 16,
  },
  statusInfo: {
    flex: 1,
  },
  statusLabel: {
    fontSize: 12,
    marginBottom: 4,
  },
  statusValue: {
    fontSize: 16,
    fontWeight: '600',
  },
  infoCard: {
    borderRadius: 12,
    borderWidth: 1,
    padding: 16,
    marginBottom: 12,
  },
  infoLabel: {
    fontSize: 12,
    fontWeight: '500',
    marginBottom: 6,
  },
  infoValue: {
    fontSize: 14,
    lineHeight: 20,
  },
  closeButton: {
    marginHorizontal: 16,
    marginBottom: 16,
    paddingVertical: 12,
    borderRadius: 8,
  },
  closeButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
    textAlign: 'center',
  },
});
