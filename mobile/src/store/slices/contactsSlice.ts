import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import { Contact, ContactGroup } from '@types';
import * as contactService from '@services/contacts';

interface ContactState {
  list: Contact[];
  groups: ContactGroup[];
  isLoading: boolean;
  error: string | null;
  pagination: {
    page: number;
    perPage: number;
    total: number;
    totalPages: number;
  };
}

const initialState: ContactState = {
  list: [],
  groups: [],
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
export const fetchContacts = createAsyncThunk(
  'contacts/fetchList',
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
      return await contactService.getContacts(params);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const fetchContactGroups = createAsyncThunk(
  'contacts/fetchGroups',
  async (_, { rejectWithValue }) => {
    try {
      return await contactService.getContactGroups();
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const createContact = createAsyncThunk(
  'contacts/create',
  async (data: Partial<Contact>, { rejectWithValue }) => {
    try {
      return await contactService.createContact(data);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const updateContact = createAsyncThunk(
  'contacts/update',
  async ({ id, data }: { id: string; data: Partial<Contact> }, { rejectWithValue }) => {
    try {
      return await contactService.updateContact(id, data);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

export const bulkCreateContacts = createAsyncThunk(
  'contacts/bulkCreate',
  async (contacts: Partial<Contact>[], { rejectWithValue }) => {
    try {
      return await contactService.bulkCreateContacts(contacts);
    } catch (error: any) {
      return rejectWithValue(error.message);
    }
  }
);

const contactsSlice = createSlice({
  name: 'contacts',
  initialState,
  reducers: {
    clearError: (state) => {
      state.error = null;
    },
  },
  extraReducers: (builder) => {
    // Fetch Contacts List
    builder
      .addCase(fetchContacts.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(fetchContacts.fulfilled, (state, action) => {
        state.isLoading = false;
        state.list = action.payload.data;
        state.pagination = {
          page: action.payload.pagination.page,
          perPage: action.payload.pagination.per_page,
          total: action.payload.pagination.total,
          totalPages: action.payload.pagination.total_pages,
        };
      })
      .addCase(fetchContacts.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Fetch Contact Groups
    builder
      .addCase(fetchContactGroups.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(fetchContactGroups.fulfilled, (state, action) => {
        state.isLoading = false;
        state.groups = action.payload;
      })
      .addCase(fetchContactGroups.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Create Contact
    builder
      .addCase(createContact.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(createContact.fulfilled, (state, action) => {
        state.isLoading = false;
        state.list.unshift(action.payload);
      })
      .addCase(createContact.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });

    // Update Contact
    builder
      .addCase(updateContact.fulfilled, (state, action) => {
        const index = state.list.findIndex((c) => c.id === action.payload.id);
        if (index !== -1) {
          state.list[index] = action.payload;
        }
      })
      .addCase(updateContact.rejected, (state, action) => {
        state.error = action.payload as string;
      });

    // Bulk Create Contacts
    builder
      .addCase(bulkCreateContacts.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(bulkCreateContacts.fulfilled, (state, action) => {
        state.isLoading = false;
        // Result is typically job info, not contacts
      })
      .addCase(bulkCreateContacts.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      });
  },
});

export const { clearError } = contactsSlice.actions;
export default contactsSlice.reducer;
