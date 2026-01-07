import { createSlice, createAsyncThunk, PayloadAction } from '@reduxjs/toolkit';
import { Agent, AgentDetail, AgentExecution, AgentExecutionRequest } from '@types';
import * as agentService from '@services/agents';

interface AgentsState {
  list: Agent[];
  current: AgentDetail | null;
  isLoading: boolean;
  error: string | null;
  execution: AgentExecution | null;
}

const initialState: AgentsState = {
  list: [],
  current: null,
  isLoading: false,
  error: null,
  execution: null,
};

// Async Thunks
export const fetchAgents = createAsyncThunk(
  'agents/fetchAgents',
  async (_, { rejectWithValue }) => {
    try {
      const response = await agentService.getAgents();
      return response.agents;
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const fetchAgentDetail = createAsyncThunk(
  'agents/fetchAgentDetail',
  async (id: string, { rejectWithValue }) => {
    try {
      return await agentService.getAgent(id);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const executeAgentAsync = createAsyncThunk(
  'agents/executeAgent',
  async (
    { agentId, request }: { agentId: string; request: AgentExecutionRequest },
    { rejectWithValue }
  ) => {
    try {
      return await agentService.executeAgent(agentId, request);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

// Slice
const agentsSlice = createSlice({
  name: 'agents',
  initialState,
  reducers: {
    clearCurrentAgent: (state) => {
      state.current = null;
    },
    setExecution: (state, action: PayloadAction<AgentExecution>) => {
      state.execution = action.payload;
    },
    clearExecution: (state) => {
      state.execution = null;
    },
  },
  extraReducers: (builder) => {
    // Fetch agents
    builder
      .addCase(fetchAgents.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(fetchAgents.fulfilled, (state, action) => {
        state.isLoading = false;
        state.list = action.payload;
      })
      .addCase(fetchAgents.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Fetch agent detail
    builder
      .addCase(fetchAgentDetail.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(fetchAgentDetail.fulfilled, (state, action) => {
        state.isLoading = false;
        state.current = action.payload;
      })
      .addCase(fetchAgentDetail.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Execute agent
    builder
      .addCase(executeAgentAsync.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(executeAgentAsync.fulfilled, (state, action) => {
        state.isLoading = false;
        state.execution = action.payload;
      })
      .addCase(executeAgentAsync.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });
  },
});

export const { clearCurrentAgent, setExecution, clearExecution } = agentsSlice.actions;
export default agentsSlice.reducer;
