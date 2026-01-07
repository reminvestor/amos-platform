import { createSlice, createAsyncThunk, PayloadAction } from '@reduxjs/toolkit';
import { Task, TaskDetail } from '@types';
import * as taskService from '@services/tasks';

interface TasksState {
  list: Task[];
  current: TaskDetail | null;
  isLoading: boolean;
  error: string | null;
  pagination: {
    page: number;
    perPage: number;
    total: number;
    hasNext: boolean;
  };
  filters: {
    status?: string;
    priority?: string;
    search?: string;
  };
}

const initialState: TasksState = {
  list: [],
  current: null,
  isLoading: false,
  error: null,
  pagination: {
    page: 1,
    perPage: 20,
    total: 0,
    hasNext: false,
  },
  filters: {},
};

// Async Thunks
export const fetchTasks = createAsyncThunk(
  'tasks/fetchTasks',
  async (
    params: {
      page?: number;
      perPage?: number;
      search?: string;
      status?: string;
      priority?: string;
    },
    { rejectWithValue }
  ) => {
    try {
      return await taskService.getTasks(params);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const fetchTaskDetail = createAsyncThunk(
  'tasks/fetchTaskDetail',
  async (id: string, { rejectWithValue }) => {
    try {
      return await taskService.getTask(id);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const createTask = createAsyncThunk(
  'tasks/createTask',
  async (data: Partial<Task>, { rejectWithValue }) => {
    try {
      return await taskService.createTask(data);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const updateTaskAsync = createAsyncThunk(
  'tasks/updateTask',
  async (
    { id, data }: { id: string; data: Partial<Task> },
    { rejectWithValue }
  ) => {
    try {
      return await taskService.updateTask(id, data);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const completeTaskAsync = createAsyncThunk(
  'tasks/completeTask',
  async (id: string, { rejectWithValue }) => {
    try {
      return await taskService.completeTask(id);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const deleteTaskAsync = createAsyncThunk(
  'tasks/deleteTask',
  async (id: string, { rejectWithValue }) => {
    try {
      await taskService.deleteTask(id);
      return id;
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const fetchTasksDueToday = createAsyncThunk(
  'tasks/fetchTasksDueToday',
  async (_, { rejectWithValue }) => {
    try {
      return await taskService.getTasksDueToday();
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const fetchOverdueTasks = createAsyncThunk(
  'tasks/fetchOverdueTasks',
  async (_, { rejectWithValue }) => {
    try {
      return await taskService.getOverdueTasks();
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

// Slice
const tasksSlice = createSlice({
  name: 'tasks',
  initialState,
  reducers: {
    setFilters: (state, action: PayloadAction<Partial<typeof state.filters>>) => {
      state.filters = { ...state.filters, ...action.payload };
    },
    clearFilters: (state) => {
      state.filters = {};
    },
    clearCurrentTask: (state) => {
      state.current = null;
    },
  },
  extraReducers: (builder) => {
    // Fetch tasks
    builder
      .addCase(fetchTasks.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(fetchTasks.fulfilled, (state, action: any) => {
        state.isLoading = false;
        state.list = action.payload.data;
        state.pagination = {
          page: action.payload.pagination.page,
          perPage: action.payload.pagination.per_page,
          total: action.payload.pagination.total,
          hasNext: action.payload.pagination.has_next,
        };
      })
      .addCase(fetchTasks.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Fetch task detail
    builder
      .addCase(fetchTaskDetail.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(fetchTaskDetail.fulfilled, (state, action) => {
        state.isLoading = false;
        state.current = action.payload;
      })
      .addCase(fetchTaskDetail.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Create task
    builder
      .addCase(createTask.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(createTask.fulfilled, (state, action) => {
        state.isLoading = false;
        state.list.unshift(action.payload);
        state.pagination.total += 1;
      })
      .addCase(createTask.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Update task
    builder
      .addCase(updateTaskAsync.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(updateTaskAsync.fulfilled, (state, action) => {
        state.isLoading = false;
        const index = state.list.findIndex((t) => t.id === action.payload.id);
        if (index > -1) {
          state.list[index] = action.payload;
        }
        if (state.current?.id === action.payload.id) {
          state.current = action.payload as TaskDetail;
        }
      })
      .addCase(updateTaskAsync.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Complete task
    builder
      .addCase(completeTaskAsync.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(completeTaskAsync.fulfilled, (state, action) => {
        state.isLoading = false;
        const index = state.list.findIndex((t) => t.id === action.payload.id);
        if (index > -1) {
          state.list[index] = action.payload;
        }
        if (state.current?.id === action.payload.id) {
          state.current = action.payload as TaskDetail;
        }
      })
      .addCase(completeTaskAsync.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Delete task
    builder
      .addCase(deleteTaskAsync.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(deleteTaskAsync.fulfilled, (state, action) => {
        state.isLoading = false;
        state.list = state.list.filter((t) => t.id !== action.payload);
        state.pagination.total -= 1;
        if (state.current?.id === action.payload) {
          state.current = null;
        }
      })
      .addCase(deleteTaskAsync.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Fetch tasks due today
    builder
      .addCase(fetchTasksDueToday.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(fetchTasksDueToday.fulfilled, (state, action) => {
        state.isLoading = false;
        state.list = action.payload;
      })
      .addCase(fetchTasksDueToday.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Fetch overdue tasks
    builder
      .addCase(fetchOverdueTasks.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(fetchOverdueTasks.fulfilled, (state, action) => {
        state.isLoading = false;
        state.list = action.payload;
      })
      .addCase(fetchOverdueTasks.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });
  },
});

export const { setFilters, clearFilters, clearCurrentTask } = tasksSlice.actions;
export default tasksSlice.reducer;
