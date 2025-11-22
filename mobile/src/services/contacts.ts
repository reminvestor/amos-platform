import { apiClient } from './api';
import { Contact, ContactGroup, PaginatedResponse } from '@types';

/**
 * Get list of contacts with pagination and filtering
 */
export async function getContacts(params: {
  page?: number;
  perPage?: number;
  search?: string;
  status?: string;
}): Promise<PaginatedResponse<Contact>> {
  try {
    const queryParams = new URLSearchParams();
    if (params.page) queryParams.append('page', params.page.toString());
    if (params.perPage) queryParams.append('per_page', params.perPage.toString());
    if (params.search) queryParams.append('search', params.search);
    if (params.status) queryParams.append('status', params.status);

    const response = await apiClient.get<PaginatedResponse<Contact>>(
      `/api/v1/contacts?${queryParams.toString()}`
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch contacts',
      status: error.response?.status,
    };
  }
}

/**
 * Get contact detail by ID
 */
export async function getContact(id: string): Promise<Contact> {
  try {
    const response = await apiClient.get<Contact>(`/api/v1/contacts/${id}`);
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch contact',
      status: error.response?.status,
    };
  }
}

/**
 * Get all contact groups
 */
export async function getContactGroups(): Promise<ContactGroup[]> {
  try {
    const response = await apiClient.get<ContactGroup[]>('/api/v1/contact_groups');
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch contact groups',
      status: error.response?.status,
    };
  }
}

/**
 * Create single contact
 */
export async function createContact(data: Partial<Contact>): Promise<Contact> {
  try {
    const response = await apiClient.post<Contact>('/api/v1/contacts', data);
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to create contact',
      status: error.response?.status,
      details: error.response?.data,
    };
  }
}

/**
 * Update contact
 */
export async function updateContact(id: string, data: Partial<Contact>): Promise<Contact> {
  try {
    const response = await apiClient.patch<Contact>(`/api/v1/contacts/${id}`, data);
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to update contact',
      status: error.response?.status,
    };
  }
}

/**
 * Bulk create/update contacts
 */
export async function bulkCreateContacts(contacts: Partial<Contact>[]): Promise<any> {
  try {
    const response = await apiClient.post('/api/v1/contacts/bulk', {
      contacts,
    });
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to bulk import contacts',
      status: error.response?.status,
      details: error.response?.data,
    };
  }
}

/**
 * Delete contact
 */
export async function deleteContact(id: string): Promise<void> {
  try {
    await apiClient.delete(`/api/v1/contacts/${id}`);
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to delete contact',
      status: error.response?.status,
    };
  }
}

/**
 * Change contact status
 */
export async function changeContactStatus(
  id: string,
  status: 'active' | 'inactive' | 'unsubscribed'
): Promise<Contact> {
  try {
    const response = await apiClient.patch<Contact>(`/api/v1/contacts/${id}`, {
      status,
    });
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to update contact status',
      status: error.response?.status,
    };
  }
}

/**
 * Get contacts in a group
 */
export async function getGroupContacts(
  groupId: string,
  params?: { page?: number; perPage?: number }
): Promise<PaginatedResponse<Contact>> {
  try {
    const queryParams = new URLSearchParams();
    if (params?.page) queryParams.append('page', params.page.toString());
    if (params?.perPage) queryParams.append('per_page', params.perPage.toString());

    const response = await apiClient.get<PaginatedResponse<Contact>>(
      `/api/v1/contact_groups/${groupId}/contacts?${queryParams.toString()}`
    );
    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to fetch group contacts',
      status: error.response?.status,
    };
  }
}
