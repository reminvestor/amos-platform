import AsyncStorage from '@react-native-async-storage/async-storage';
import NetInfo from '@react-native-community/netinfo';

export interface QueuedRequest {
  id: string;
  method: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  url: string;
  data?: any;
  headers?: Record<string, string>;
  timestamp: number;
  retries: number;
}

const OFFLINE_QUEUE_KEY = '@offline_queue';
const MAX_RETRIES = 3;
const QUEUE_TIMEOUT = 24 * 60 * 60 * 1000; // 24 hours

class OfflineService {
  private isOnline = true;
  private networkUnsubscribe: (() => void) | null = null;
  private queue: QueuedRequest[] = [];
  private processingQueue = false;

  async initialize() {
    // Check initial network status
    const state = await NetInfo.fetch();
    this.isOnline = state.isConnected ?? true;

    // Subscribe to network changes
    this.networkUnsubscribe = NetInfo.addEventListener((state) => {
      const wasOffline = !this.isOnline;
      this.isOnline = state.isConnected ?? true;

      // When connection is restored, process queue
      if (wasOffline && this.isOnline) {
        this.processQueue();
      }
    });

    // Load queue from storage
    await this.loadQueue();

    // Process queue if online
    if (this.isOnline) {
      await this.processQueue();
    }
  }

  cleanup() {
    if (this.networkUnsubscribe) {
      this.networkUnsubscribe();
    }
  }

  getIsOnline(): boolean {
    return this.isOnline;
  }

  async addToQueue(request: QueuedRequest) {
    this.queue.push(request);
    await this.saveQueue();
  }

  async queueRequest(
    method: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE',
    url: string,
    data?: any,
    headers?: Record<string, string>
  ): Promise<void> {
    const request: QueuedRequest = {
      id: `${Date.now()}-${Math.random()}`,
      method,
      url,
      data,
      headers,
      timestamp: Date.now(),
      retries: 0,
    };

    await this.addToQueue(request);
  }

  private async saveQueue() {
    try {
      await AsyncStorage.setItem(OFFLINE_QUEUE_KEY, JSON.stringify(this.queue));
    } catch (error) {
      console.log('Error saving offline queue:', error);
    }
  }

  private async loadQueue() {
    try {
      const stored = await AsyncStorage.getItem(OFFLINE_QUEUE_KEY);
      if (stored) {
        const queue = JSON.parse(stored) as QueuedRequest[];

        // Filter out expired requests
        const now = Date.now();
        this.queue = queue.filter((req) => now - req.timestamp < QUEUE_TIMEOUT);

        if (this.queue.length !== queue.length) {
          await this.saveQueue();
        }
      }
    } catch (error) {
      console.log('Error loading offline queue:', error);
    }
  }

  async processQueue() {
    if (this.processingQueue || !this.isOnline || this.queue.length === 0) {
      return;
    }

    this.processingQueue = true;

    const failedRequests: QueuedRequest[] = [];

    for (const request of this.queue) {
      try {
        // In a real app, this would make the actual API call
        // For now, we simulate success
        console.log(`Processing queued request: ${request.method} ${request.url}`);

        // Mark request as processed by not adding to failedRequests
      } catch (error) {
        // If request failed and hasn't exceeded max retries, re-add to queue
        if (request.retries < MAX_RETRIES) {
          request.retries++;
          failedRequests.push(request);
        }
      }
    }

    // Update queue with failed requests
    this.queue = failedRequests;
    await this.saveQueue();

    this.processingQueue = false;
  }

  getQueueLength(): number {
    return this.queue.length;
  }

  getQueue(): QueuedRequest[] {
    return [...this.queue];
  }

  async clearQueue() {
    this.queue = [];
    await AsyncStorage.removeItem(OFFLINE_QUEUE_KEY);
  }
}

export const offlineService = new OfflineService();
