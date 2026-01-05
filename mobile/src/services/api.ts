import axios, { AxiosError, AxiosInstance } from 'axios';
import * as storage from '@utils/storage';
import { Config } from '@config';

class ApiClient {
  private instance: AxiosInstance;
  private isRefreshing = false;
  private failedQueue: Array<{
    onSuccess: (token: string) => void;
    onError: (error: any) => void;
  }> = [];

  constructor() {
    this.instance = axios.create({
      baseURL: Config.api.baseURL,
      timeout: Config.api.timeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    });

    this.setupInterceptors();
  }

  private setupInterceptors() {
    // Request Interceptor
    this.instance.interceptors.request.use(
      async (config) => {
        const token = await storage.getToken();
        if (token) {
          config.headers.Authorization = `Bearer ${token}`;
        }
        return config;
      },
      (error) => {
        return Promise.reject(error);
      }
    );

    // Response Interceptor
    this.instance.interceptors.response.use(
      (response) => response,
      async (error: AxiosError<any>) => {
        const originalRequest = error.config as any;

        // Handle 401 Unauthorized - Token may have expired
        if (error.response?.status === 401 && !originalRequest._retry) {
          originalRequest._retry = true;

          if (!this.isRefreshing) {
            this.isRefreshing = true;

            try {
              // Try to refresh token (you'll need to implement this on backend)
              const newToken = await this.refreshToken();

              this.isRefreshing = false;
              this.processQueue(newToken, null);
              return this.instance(originalRequest);
            } catch (refreshError) {
              this.isRefreshing = false;
              this.processQueue(null, refreshError);

              // Clear auth and redirect to login
              await storage.clearSession();
              // Navigation should be handled by AuthContext in app navigation
              return Promise.reject(refreshError);
            }
          }

          // Queue the request while token is being refreshed
          return new Promise((onSuccess, onError) => {
            this.failedQueue.push({ onSuccess, onError });
          })
            .then((token) => {
              if (token) {
                originalRequest.headers.Authorization = `Bearer ${token}`;
              }
              return this.instance(originalRequest);
            });
        }

        // Handle other errors
        return Promise.reject(error);
      }
    );
  }

  private processQueue(token: string | null, error: any) {
    this.failedQueue.forEach((request) => {
      if (token) {
        request.onSuccess(token);
      } else {
        request.onError(error);
      }
    });
    this.failedQueue = [];
  }

  private async refreshToken(): Promise<string> {
    // This would call your backend endpoint to refresh the token
    // For now, we'll just clear the session
    throw new Error('Token refresh not implemented');
  }

  getClient() {
    return this.instance;
  }

  // Generic methods
  async get<T>(url: string, config?: any) {
    const response = await this.instance.get<T>(url, config);
    return response.data;
  }

  async post<T>(url: string, data?: any, config?: any) {
    const response = await this.instance.post<T>(url, data, config);
    return response.data;
  }

  async put<T>(url: string, data?: any, config?: any) {
    const response = await this.instance.put<T>(url, data, config);
    return response.data;
  }

  async patch<T>(url: string, data?: any, config?: any) {
    const response = await this.instance.patch<T>(url, data, config);
    return response.data;
  }

  async delete<T>(url: string, config?: any) {
    const response = await this.instance.delete<T>(url, config);
    return response.data;
  }
}

export const apiClient = new ApiClient();
