import { apiClient } from './api';
import type { MFAVerifyRequest, MFAVerifyResponse, MFAResendRequest } from '@types';

/**
 * Verify MFA code
 */
export async function verifyMFACode(request: MFAVerifyRequest): Promise<MFAVerifyResponse> {
  try {
    const response = await apiClient.post<MFAVerifyResponse>('/mfa/verify', {
      mfa_session_token: request.mfa_session_token,
      code: request.code,
      backup_code: request.use_backup_code,
    });

    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'MFA verification failed',
      status: error.response?.status,
      details: error.response?.data,
    };
  }
}

/**
 * Resend MFA code (for email/SMS)
 */
export async function resendMFACode(request: MFAResendRequest): Promise<{ message: string }> {
  try {
    const response = await apiClient.post<{ message: string }>('/mfa/resend_code', {
      mfa_session_token: request.mfa_session_token,
    });

    return response;
  } catch (error: any) {
    throw {
      message: error.response?.data?.message || 'Failed to resend MFA code',
      status: error.response?.status,
      details: error.response?.data,
    };
  }
}
