import { apiClient } from './api';
import { LandingPage, LandingPageSubmission, PaginatedResponse } from '@types';

/**
 * Get list of landing pages
 */
export async function getLandingPages(params?: {
  page?: number;
  perPage?: number;
  status?: 'draft' | 'published';
}): Promise<PaginatedResponse<LandingPage>> {
  try {
    const queryParams = new URLSearchParams();
    if (params?.page) queryParams.append('page', params.page.toString());
    if (params?.perPage) queryParams.append('per_page', params.perPage.toString());
    if (params?.status) queryParams.append('status', params.status);

    const response = await apiClient.get<any>(
      `/api/v1/landing_pages?${queryParams.toString()}`
    );

    // API now returns mobile-friendly field names (view_count, submission_count)
    return {
      data: response.data || [],
      pagination: {
        page: response.pagination?.current_page || 1,
        per_page: response.pagination?.per_page || 20,
        total: response.pagination?.total_count || 0,
        total_pages: response.pagination?.total_pages || 1,
      },
    };
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch landing pages',
      status: error.response?.status,
    };
  }
}

/**
 * Get landing page detail
 */
export async function getLandingPageDetail(id: string): Promise<LandingPage> {
  try {
    const response = await apiClient.get<LandingPage>(`/api/v1/landing_pages/${id}`);
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch landing page',
      status: error.response?.status,
    };
  }
}

/**
 * Create landing page
 */
export async function createLandingPage(data: {
  title: string;
  description?: string;
  templateId?: string;
}): Promise<LandingPage> {
  try {
    const response = await apiClient.post<LandingPage>('/api/v1/landing_pages', data);
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to create landing page',
      status: error.response?.status,
    };
  }
}

/**
 * Update landing page
 */
export async function updateLandingPage(
  id: string,
  data: Partial<LandingPage>
): Promise<LandingPage> {
  try {
    const response = await apiClient.patch<LandingPage>(
      `/api/v1/landing_pages/${id}`,
      data
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to update landing page',
      status: error.response?.status,
    };
  }
}

/**
 * Publish landing page
 */
export async function publishLandingPage(id: string): Promise<LandingPage> {
  try {
    const response = await apiClient.post<LandingPage>(
      `/api/v1/landing_pages/${id}/publish`,
      {}
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to publish landing page',
      status: error.response?.status,
    };
  }
}

/**
 * Unpublish landing page
 */
export async function unpublishLandingPage(id: string): Promise<LandingPage> {
  try {
    const response = await apiClient.post<LandingPage>(
      `/api/v1/landing_pages/${id}/unpublish`,
      {}
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to unpublish landing page',
      status: error.response?.status,
    };
  }
}

/**
 * Get landing page submissions
 */
export async function getLandingPageSubmissions(
  landingPageId: string,
  params?: { page?: number; perPage?: number }
): Promise<PaginatedResponse<LandingPageSubmission>> {
  try {
    const queryParams = new URLSearchParams();
    if (params?.page) queryParams.append('page', params.page.toString());
    if (params?.perPage) queryParams.append('per_page', params.perPage.toString());

    const response = await apiClient.get<PaginatedResponse<LandingPageSubmission>>(
      `/api/v1/landing_pages/${landingPageId}/submissions?${queryParams.toString()}`
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch submissions',
      status: error.response?.status,
    };
  }
}

/**
 * Process landing page submission (mark as processed)
 */
export async function processSubmission(submissionId: string): Promise<void> {
  try {
    await apiClient.post(
      `/api/v1/landing_page_submissions/${submissionId}/process`,
      {}
    );
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to process submission',
      status: error.response?.status,
    };
  }
}

/**
 * Mark submission as spam
 */
export async function markSubmissionAsSpam(submissionId: string): Promise<void> {
  try {
    await apiClient.post(
      `/api/v1/landing_page_submissions/${submissionId}/spam`,
      {}
    );
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to mark as spam',
      status: error.response?.status,
    };
  }
}

/**
 * Delete landing page
 */
export async function deleteLandingPage(id: string): Promise<void> {
  try {
    await apiClient.delete(`/api/v1/landing_pages/${id}`);
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to delete landing page',
      status: error.response?.status,
    };
  }
}
