import { apiClient } from './api';
import { Campaign, CampaignDetail, PaginatedResponse } from '@types';

/**
 * Get list of campaigns with pagination and filtering
 */
export async function getCampaigns(params: {
  page?: number;
  perPage?: number;
  search?: string;
  status?: string;
}): Promise<PaginatedResponse<Campaign>> {
  try {
    const queryParams = new URLSearchParams();
    if (params.page) queryParams.append('page', params.page.toString());
    if (params.perPage) queryParams.append('per_page', params.perPage.toString());
    if (params.search) queryParams.append('search', params.search);
    if (params.status) queryParams.append('status', params.status);

    const response = await apiClient.get<PaginatedResponse<Campaign>>(
      `/api/v1/campaigns?${queryParams.toString()}`
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch campaigns',
      status: error.response?.status,
    };
  }
}

/**
 * Get campaign detail by ID
 */
export async function getCampaignDetail(id: string): Promise<CampaignDetail> {
  try {
    const response = await apiClient.get<CampaignDetail>(`/api/v1/campaigns/${id}`);
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch campaign',
      status: error.response?.status,
    };
  }
}

/**
 * Get campaign analytics/stats
 */
export async function getCampaignAnalytics(id: string): Promise<any> {
  try {
    const response = await apiClient.get(`/api/v1/campaigns/${id}/analytics`);
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch campaign analytics',
      status: error.response?.status,
    };
  }
}

/**
 * Create new campaign
 */
export async function createCampaign(data: Partial<Campaign>): Promise<Campaign> {
  try {
    const response = await apiClient.post<Campaign>('/api/v1/campaigns', data);
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to create campaign',
      status: error.response?.status,
      details: error.response?.data,
    };
  }
}

/**
 * Update campaign
 */
export async function updateCampaign(id: string, data: Partial<Campaign>): Promise<Campaign> {
  try {
    const response = await apiClient.patch<Campaign>(`/api/v1/campaigns/${id}`, data);
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to update campaign',
      status: error.response?.status,
    };
  }
}

/**
 * Pause campaign
 */
export async function pauseCampaign(id: string): Promise<Campaign> {
  try {
    const response = await apiClient.patch<Campaign>(`/api/v1/campaigns/${id}`, {
      status: 'paused',
    });
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to pause campaign',
      status: error.response?.status,
    };
  }
}

/**
 * Resume campaign
 */
export async function resumeCampaign(id: string): Promise<Campaign> {
  try {
    const response = await apiClient.patch<Campaign>(`/api/v1/campaigns/${id}`, {
      status: 'in_progress',
    });
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to resume campaign',
      status: error.response?.status,
    };
  }
}

/**
 * Delete campaign
 */
export async function deleteCampaign(id: string): Promise<void> {
  try {
    await apiClient.delete(`/api/v1/campaigns/${id}`);
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to delete campaign',
      status: error.response?.status,
    };
  }
}

/**
 * Duplicate campaign
 */
export async function duplicateCampaign(id: string): Promise<Campaign> {
  try {
    const response = await apiClient.post<Campaign>(`/api/v1/campaigns/${id}/duplicate`, {});
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to duplicate campaign',
      status: error.response?.status,
    };
  }
}

/**
 * Test send campaign to email
 */
export async function testSendCampaign(id: string, email: string): Promise<void> {
  try {
    await apiClient.post(`/api/v1/campaigns/${id}/test_send`, { email });
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to send test email',
      status: error.response?.status,
    };
  }
}
