import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import { Campaign, CampaignDetail, PaginationParams } from '@types';
import * as campaignService from '@services/campaigns';

interface CampaignState {
  list: Campaign[];
  current: CampaignDetail | null;
  isLoading: boolean;
  error: string | null;
  pagination: {
    page: number;
    perPage: number;
    total: number;
    totalPages: number;
  };
}

const initialState: CampaignState = {
  list: [],
  current: null,
  isLoading: false,
  error: null,
  pagination: {
    page: 1,
    perPage: 20,
    total: 0,
    totalPages: 0,
  },
};

// Async Thunks
export const fetchCampaigns = createAsyncThunk(
  'campaigns/fetchList',
  async (
    params: {
      page?: number;
      perPage?: number;
      search?: string;
      status?: string;
    },
    { rejectWithValue }
  ) => {
    try {
      return await campaignService.getCampaigns(params);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const fetchCampaignDetail = createAsyncThunk(
  'campaigns/fetchDetail',
  async (id: string, { rejectWithValue }) => {
    try {
      return await campaignService.getCampaignDetail(id);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const pauseCampaign = createAsyncThunk(
  'campaigns/pause',
  async (id: string, { rejectWithValue }) => {
    try {
      return await campaignService.pauseCampaign(id);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const resumeCampaign = createAsyncThunk(
  'campaigns/resume',
  async (id: string, { rejectWithValue }) => {
    try {
      return await campaignService.resumeCampaign(id);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

const campaignsSlice = createSlice({
  name: 'campaigns',
  initialState,
  reducers: {
    clearError: (state) => {
      state.error = null;
    },
    setCurrent: (state, action) => {
      state.current = action.payload;
    },
    clearCurrent: (state) => {
      state.current = null;
    },
  },
  extraReducers: (builder) => {
    // Fetch Campaigns List
    builder
      .addCase(fetchCampaigns.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(fetchCampaigns.fulfilled, (state, action) => {
        state.isLoading = false;
        state.list = action.payload.data;
        state.pagination = {
          page: action.payload.pagination.page,
          perPage: action.payload.pagination.per_page,
          total: action.payload.pagination.total,
          totalPages: action.payload.pagination.total_pages,
        };
      })
      .addCase(fetchCampaigns.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Fetch Campaign Detail
    builder
      .addCase(fetchCampaignDetail.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(fetchCampaignDetail.fulfilled, (state, action) => {
        state.isLoading = false;
        state.current = action.payload;
      })
      .addCase(fetchCampaignDetail.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Pause Campaign
    builder
      .addCase(pauseCampaign.fulfilled, (state, action) => {
        if (state.current && state.current.id === action.payload.id) {
          state.current.status = 'paused';
        }
        const index = state.list.findIndex((c) => c.id === action.payload.id);
        if (index !== -1) {
          state.list[index].status = 'paused';
        }
      })
      .addCase(pauseCampaign.rejected, (state, action) => {
        state.error = action.payload as string;
      });

    // Resume Campaign
    builder
      .addCase(resumeCampaign.fulfilled, (state, action) => {
        if (state.current && state.current.id === action.payload.id) {
          state.current.status = action.payload.status;
        }
        const index = state.list.findIndex((c) => c.id === action.payload.id);
        if (index !== -1) {
          state.list[index].status = action.payload.status;
        }
      })
      .addCase(resumeCampaign.rejected, (state, action) => {
        state.error = action.payload as string;
      });
  },
});

export const { clearError, setCurrent, clearCurrent } = campaignsSlice.actions;
export default campaignsSlice.reducer;
