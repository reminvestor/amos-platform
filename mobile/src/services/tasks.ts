import { apiClient } from './api';
import { Task, TaskDetail, PaginatedResponse } from '@types';

/**
 * Get list of tasks with pagination and filtering
 */
export async function getTasks(params: {
  page?: number;
  perPage?: number;
  search?: string;
  status?: string;
  priority?: string;
  due_date?: string;
}): Promise<PaginatedResponse<Task>> {
  try {
    const queryParams = new URLSearchParams();
    if (params.page) queryParams.append('page', params.page.toString());
    if (params.perPage) queryParams.append('per_page', params.perPage.toString());
    if (params.search) queryParams.append('search', params.search);
    if (params.status) queryParams.append('status', params.status);
    if (params.priority) queryParams.append('priority', params.priority);
    if (params.due_date) queryParams.append('due_date', params.due_date);

    const response = await apiClient.get<PaginatedResponse<Task>>(
      `/api/v1/tasks?${queryParams.toString()}`
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch tasks',
      status: error.response?.status,
    };
  }
}

/**
 * Get task detail by ID
 */
export async function getTask(id: string): Promise<TaskDetail> {
  try {
    const response = await apiClient.get<TaskDetail>(`/api/v1/tasks/${id}`);
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch task',
      status: error.response?.status,
    };
  }
}

/**
 * Create new task
 */
export async function createTask(data: Partial<Task>): Promise<Task> {
  try {
    const response = await apiClient.post<Task>('/api/v1/tasks', data);
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to create task',
      status: error.response?.status,
      details: error.response?.data,
    };
  }
}

/**
 * Update task
 */
export async function updateTask(id: string, data: Partial<Task>): Promise<Task> {
  try {
    const response = await apiClient.patch<Task>(`/api/v1/tasks/${id}`, data);
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to update task',
      status: error.response?.status,
    };
  }
}

/**
 * Mark task as complete
 */
export async function completeTask(id: string): Promise<Task> {
  try {
    const response = await apiClient.patch<Task>(`/api/v1/tasks/${id}`, {
      status: 'completed',
      completed_at: new Date().toISOString(),
    });
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to complete task',
      status: error.response?.status,
    };
  }
}

/**
 * Delete task
 */
export async function deleteTask(id: string): Promise<void> {
  try {
    await apiClient.delete(`/api/v1/tasks/${id}`);
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to delete task',
      status: error.response?.status,
    };
  }
}

/**
 * Get tasks by related entity
 */
export async function getTasksByEntity(
  entityType: string,
  entityId: string
): Promise<Task[]> {
  try {
    const response = await apiClient.get<Task[]>(
      `/api/v1/tasks/entity/${entityType}/${entityId}`
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch related tasks',
      status: error.response?.status,
    };
  }
}

/**
 * Get tasks due today
 */
export async function getTasksDueToday(): Promise<Task[]> {
  try {
    const response = await apiClient.get<Task[]>('/api/v1/tasks/due-today');
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch today\'s tasks',
      status: error.response?.status,
    };
  }
}

/**
 * Get overdue tasks
 */
export async function getOverdueTasks(): Promise<Task[]> {
  try {
    const response = await apiClient.get<Task[]>('/api/v1/tasks/overdue');
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch overdue tasks',
      status: error.response?.status,
    };
  }
}

/**
 * Get task statistics
 */
export async function getTaskStats(): Promise<{
  total: number;
  pending: number;
  inProgress: number;
  completed: number;
  overdue: number;
  dueTodayCount: number;
}> {
  try {
    const response = await apiClient.get('/api/v1/tasks/stats');
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch task statistics',
      status: error.response?.status,
    };
  }
}
