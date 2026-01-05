import { createSlice, PayloadAction } from '@reduxjs/toolkit';

interface FavoritesState {
  campaignIds: string[];
  contactIds: string[];
}

const initialState: FavoritesState = {
  campaignIds: [],
  contactIds: [],
};

const favoritesSlice = createSlice({
  name: 'favorites',
  initialState,
  reducers: {
    toggleCampaignFavorite: (state, action: PayloadAction<string>) => {
      const id = action.payload;
      const index = state.campaignIds.indexOf(id);
      if (index > -1) {
        state.campaignIds.splice(index, 1);
      } else {
        state.campaignIds.push(id);
      }
    },
    toggleContactFavorite: (state, action: PayloadAction<string>) => {
      const id = action.payload;
      const index = state.contactIds.indexOf(id);
      if (index > -1) {
        state.contactIds.splice(index, 1);
      } else {
        state.contactIds.push(id);
      }
    },
    addCampaignFavorite: (state, action: PayloadAction<string>) => {
      if (!state.campaignIds.includes(action.payload)) {
        state.campaignIds.push(action.payload);
      }
    },
    removeCampaignFavorite: (state, action: PayloadAction<string>) => {
      state.campaignIds = state.campaignIds.filter((id) => id !== action.payload);
    },
    addContactFavorite: (state, action: PayloadAction<string>) => {
      if (!state.contactIds.includes(action.payload)) {
        state.contactIds.push(action.payload);
      }
    },
    removeContactFavorite: (state, action: PayloadAction<string>) => {
      state.contactIds = state.contactIds.filter((id) => id !== action.payload);
    },
    setFavoriteCampaigns: (state, action: PayloadAction<string[]>) => {
      state.campaignIds = action.payload;
    },
    setFavoriteContacts: (state, action: PayloadAction<string[]>) => {
      state.contactIds = action.payload;
    },
  },
});

export const {
  toggleCampaignFavorite,
  toggleContactFavorite,
  addCampaignFavorite,
  removeCampaignFavorite,
  addContactFavorite,
  removeContactFavorite,
  setFavoriteCampaigns,
  setFavoriteContacts,
} = favoritesSlice.actions;

export default favoritesSlice.reducer;
