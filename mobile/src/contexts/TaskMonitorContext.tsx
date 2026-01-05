import React, { createContext, useContext, useState, useCallback, useEffect, useRef } from 'react';

export interface AgentTask {
  task_id: string;
  status: 'queued' | 'running' | 'processing' | 'completed' | 'failed' | 'waiting_for_input';
  progress: number;
  message: string;
  agent_type?: string;
  started_at?: string;
  duration?: number;
  error?: string;
}

interface TaskMonitorContextType {
  tasks: AgentTask[];
  activeTasks: AgentTask[];
  addOrUpdateTask: (task: AgentTask) => void;
  removeTask: (taskId: string) => void;
  clearCompletedTasks: () => void;
  isExpanded: boolean;
  setIsExpanded: (expanded: boolean) => void;
}

const TaskMonitorContext = createContext<TaskMonitorContextType | undefined>(undefined);

export function TaskMonitorProvider({ children }: { children: React.ReactNode }) {
  const [tasks, setTasks] = useState<AgentTask[]>([]);
  const [isExpanded, setIsExpanded] = useState(false);
  const durationIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // Filter to get only active tasks
  const activeTasks = tasks.filter(
    (t) => t.status === 'running' || t.status === 'processing' || t.status === 'queued' || t.status === 'waiting_for_input'
  );

  // Update durations every second for active tasks
  useEffect(() => {
    durationIntervalRef.current = setInterval(() => {
      setTasks((prevTasks) =>
        prevTasks.map((task) => {
          if (
            task.started_at &&
            (task.status === 'running' || task.status === 'processing' || task.status === 'waiting_for_input')
          ) {
            const startTime = new Date(task.started_at).getTime();
            const duration = Math.floor((Date.now() - startTime) / 1000);
            return { ...task, duration };
          }
          return task;
        })
      );
    }, 1000);

    return () => {
      if (durationIntervalRef.current) {
        clearInterval(durationIntervalRef.current);
      }
    };
  }, []);

  const addOrUpdateTask = useCallback((task: AgentTask) => {
    setTasks((prevTasks) => {
      const existingIndex = prevTasks.findIndex((t) => t.task_id === task.task_id);

      if (existingIndex >= 0) {
        // Update existing task
        const updated = [...prevTasks];
        updated[existingIndex] = {
          ...updated[existingIndex],
          ...task,
          // Keep started_at if already set
          started_at: updated[existingIndex].started_at || task.started_at,
        };
        return updated;
      } else {
        // Add new task
        const newTask: AgentTask = {
          ...task,
          started_at: task.started_at || new Date().toISOString(),
        };
        return [...prevTasks, newTask];
      }
    });

    // Auto-expand when a new task starts
    if (task.status === 'running' || task.status === 'processing') {
      setIsExpanded(true);
    }
  }, []);

  const removeTask = useCallback((taskId: string) => {
    setTasks((prevTasks) => prevTasks.filter((t) => t.task_id !== taskId));
  }, []);

  const clearCompletedTasks = useCallback(() => {
    setTasks((prevTasks) =>
      prevTasks.filter((t) => t.status !== 'completed' && t.status !== 'failed')
    );
  }, []);

  return (
    <TaskMonitorContext.Provider
      value={{
        tasks,
        activeTasks,
        addOrUpdateTask,
        removeTask,
        clearCompletedTasks,
        isExpanded,
        setIsExpanded,
      }}
    >
      {children}
    </TaskMonitorContext.Provider>
  );
}

export function useTaskMonitor() {
  const context = useContext(TaskMonitorContext);
  if (!context) {
    throw new Error('useTaskMonitor must be used within a TaskMonitorProvider');
  }
  return context;
}

/**
 * Parse SSE event data for task updates
 */
export function parseTaskEvent(data: any): AgentTask | null {
  if (!data) return null;

  const eventType = data.type;

  // Handle different event types
  if (eventType === 'task_progress' || eventType === 'task_update') {
    return {
      task_id: data.task_id || data.id || `task-${Date.now()}`,
      status: data.status || 'running',
      progress: data.progress || 0,
      message: data.message || data.description || '',
      agent_type: data.agent_type || data.workflow_type,
      started_at: data.started_at,
    };
  }

  if (eventType === 'task_completed') {
    return {
      task_id: data.task_id || data.id || `task-${Date.now()}`,
      status: 'completed',
      progress: 100,
      message: data.message || 'Task completed',
      agent_type: data.agent_type || data.workflow_type,
      started_at: data.started_at,
    };
  }

  if (eventType === 'task_failed') {
    return {
      task_id: data.task_id || data.id || `task-${Date.now()}`,
      status: 'failed',
      progress: data.progress || 0,
      message: data.message || 'Task failed',
      agent_type: data.agent_type || data.workflow_type,
      error: data.error,
      started_at: data.started_at,
    };
  }

  if (eventType === 'user_input_required') {
    return {
      task_id: data.task_id || data.id || `task-${Date.now()}`,
      status: 'waiting_for_input',
      progress: data.progress || 50,
      message: data.message || 'Waiting for input',
      agent_type: data.agent_type || data.workflow_type,
      started_at: data.started_at,
    };
  }

  return null;
}
