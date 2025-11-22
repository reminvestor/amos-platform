/**
 * Core Type Definitions for AMOS Mobile App
 */

// Authentication
export interface User {
  id: string;
  email: string;
  name: string;
  role: 'admin' | 'marketer' | 'viewer';
  entity_id: string;
  api_key?: string;
  created_at?: string;
  updated_at?: string;
}

export interface AuthState {
  user: User | null;
  token: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;
}

export interface LoginCredentials {
  email: string;
  password: string;
}

export interface LoginResponse {
  user: User;
  api_key: string;
  token: string;
}

// Entity
export interface Entity {
  id: string;
  name: string;
  timezone?: string;
  currency?: string;
  logo_url?: string;
  subscription_plan: 'free' | 'starter' | 'pro' | 'enterprise';
  created_at: string;
  updated_at: string;
}

// Campaign
export interface Campaign {
  id: string;
  entity_id: string;
  user_id: string;
  name: string;
  subject: string;
  status: 'draft' | 'scheduled' | 'in_progress' | 'completed' | 'paused' | 'stopped';
  created_at: string;
  updated_at: string;
  scheduled_at?: string;
  contact_count?: number;
  open_rate?: number;
  click_rate?: number;
  bounce_rate?: number;
  mailgun_stats?: MailgunStats;
}

export interface MailgunStats {
  delivered: number;
  failed: number;
  bounced: number;
  unsubscribed: number;
  complained: number;
  opened: number;
  clicked: number;
}

export interface CampaignDetail extends Campaign {
  email_template?: EmailTemplate;
  contact_groups?: ContactGroup[];
  email_count?: number;
  delivery_start_time?: string;
}

// Email Template
export interface EmailTemplate {
  id: string;
  entity_id: string;
  name: string;
  subject: string;
  body: string;
  created_at: string;
  updated_at: string;
}

// Contact
export interface Contact {
  id: string;
  entity_id: string;
  email: string;
  status: 'active' | 'inactive' | 'unsubscribed';
  metadata?: Record<string, any>;
  created_at: string;
  updated_at: string;
  name?: string;
  company?: string;
}

export interface ContactGroup {
  id: string;
  entity_id: string;
  name: string;
  description?: string;
  contact_count?: number;
  created_at: string;
  updated_at: string;
}

// Landing Page
export interface LandingPage {
  id: string;
  entity_id: string;
  title: string;
  slug: string;
  status: 'draft' | 'published';
  html_content: string;
  created_at: string;
  updated_at: string;
  submission_count?: number;
  view_count?: number;
  published_at?: string;
}

export interface LandingPageSubmission {
  id: string;
  landing_page_id: string;
  email: string;
  data?: Record<string, any>;
  ip_address?: string;
  user_agent?: string;
  created_at: string;
}

// Chat/AI
export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: string;
  is_streaming?: boolean;
  metadata?: Record<string, any>;
}

export interface ChatContext {
  messages: ChatMessage[];
  entity_id: string;
  user_id: string;
}

// Voice
export interface VoiceSession {
  id: string;
  status: 'active' | 'inactive';
  transcript?: string;
  duration?: number;
  error?: string;
}

// Push Notifications
export interface PushNotification {
  id: string;
  user_id: string;
  title: string;
  body: string;
  type: 'campaign' | 'submission' | 'alert' | 'general';
  related_id?: string;
  read: boolean;
  created_at: string;
}

// API Response
export interface ApiResponse<T = any> {
  data: T;
  status: number;
  message?: string;
}

export interface ApiError {
  error: boolean;
  message: string;
  code: string;
  status: number;
  details?: Record<string, any>;
}

// Pagination
export interface PaginationParams {
  page: number;
  per_page: number;
  search?: string;
  sort?: string;
  order?: 'asc' | 'desc';
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    page: number;
    per_page: number;
    total: number;
    total_pages: number;
    has_next: boolean;
    has_prev: boolean;
  };
}

// Redux State
export interface AppState {
  auth: AuthState;
  campaigns: {
    list: Campaign[];
    current: CampaignDetail | null;
    isLoading: boolean;
    error: string | null;
    pagination: PaginationParams;
  };
  contacts: {
    list: Contact[];
    groups: ContactGroup[];
    isLoading: boolean;
    error: string | null;
    pagination: PaginationParams;
  };
  landingPages: {
    list: LandingPage[];
    current: LandingPage | null;
    submissions: LandingPageSubmission[];
    isLoading: boolean;
    error: string | null;
  };
  chat: {
    messages: ChatMessage[];
    isLoading: boolean;
    error: string | null;
  };
  ui: {
    theme: 'light' | 'dark';
    fontSize: 'small' | 'medium' | 'large';
    isOnline: boolean;
    notificationSettings: NotificationSettings;
  };
}

export interface NotificationSettings {
  campaignStatus: boolean;
  formSubmissions: boolean;
  alerts: boolean;
  general: boolean;
}

// Storage Types
export interface StoredSession {
  token: string;
  user: User;
  expiresAt: number;
}

// Async Thunk Payload Types
export interface ThunkConfig {
  rejectValue: ApiError;
}
