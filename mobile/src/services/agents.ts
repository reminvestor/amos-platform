import apiClient from './api';
import { Agent, AgentDetail, AgentExecution, AgentExecutionRequest } from '@types';

/**
 * Fetch all available agents for the current entity
 */
export async function getAgents(): Promise<{ agents: Agent[]; total: number }> {
  try {
    const response = await apiClient.get('/api/v1/agents');
    return response.data;
  } catch (error: any) {
    console.error('Error fetching agents:', error);
    throw error;
  }
}

/**
 * Fetch a specific agent with full details
 */
export async function getAgent(id: string): Promise<AgentDetail> {
  try {
    const response = await apiClient.get(`/api/v1/agents/${id}`);
    return response.data;
  } catch (error: any) {
    console.error(`Error fetching agent ${id}:`, error);
    throw error;
  }
}

/**
 * Execute an agent with the given task
 */
export async function executeAgent(
  agentId: string,
  request: AgentExecutionRequest
): Promise<AgentExecution> {
  try {
    const response = await apiClient.post(`/api/v1/agents/${agentId}/execute`, {
      task: request.task,
      context: request.context
    });
    return response.data;
  } catch (error: any) {
    console.error(`Error executing agent ${agentId}:`, error);
    throw error;
  }
}

/**
 * Get available agent types
 */
export async function getAgentTypes(): Promise<
  { key: string; label: string }[]
> {
  try {
    const response = await apiClient.get('/api/v1/agents/agent_types');
    return response.data.types;
  } catch (error: any) {
    console.error('Error fetching agent types:', error);
    throw error;
  }
}

/**
 * Get icon name for agent type
 */
export function getIconForAgentType(
  agentType: string
): string {
  const iconMap: Record<string, string> = {
    content_generator: 'file-document-plus',
    data_processor: 'chart-line',
    api_integration: 'api',
    workflow_automation: 'workflow',
    custom: 'robot'
  };
  return iconMap[agentType] || 'robot';
}

/**
 * Get label for agent type
 */
export function getLabelForAgentType(agentType: string): string {
  const labelMap: Record<string, string> = {
    content_generator: 'Content Generator',
    data_processor: 'Data Processor',
    api_integration: 'API Integration',
    workflow_automation: 'Workflow Automation',
    custom: 'Custom Agent'
  };
  return labelMap[agentType] || agentType;
}
