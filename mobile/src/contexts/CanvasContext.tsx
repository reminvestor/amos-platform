import React, { createContext, useContext, useState, useCallback, ReactNode } from 'react';

// Canvas types supported (matching web app)
export type CanvasType =
  | 'document_viewer'
  | 'document_list'
  | 'document_search_results'
  | 'landing_page_viewer'
  | 'landing_page_details'
  | 'campaign_viewer'
  | 'contact_viewer'
  | 'analytics_dashboard'
  | 'task_progress'
  | 'integrations_manager'
  | null;

export interface CanvasData {
  asset_id?: string;
  document_id?: string;
  landing_page_id?: string;
  campaign_id?: string;
  contact_id?: string;
  query?: string;
  results?: any[];
  title?: string;
  [key: string]: any;
}

export interface CanvasState {
  type: CanvasType;
  data: CanvasData;
  title: string;
  isVisible: boolean;
}

interface CanvasContextValue {
  canvas: CanvasState;
  loadCanvas: (type: CanvasType, data?: CanvasData, title?: string) => void;
  closeCanvas: () => void;
  updateCanvasData: (data: Partial<CanvasData>) => void;
  isCanvasVisible: boolean;
}

const defaultCanvas: CanvasState = {
  type: null,
  data: {},
  title: '',
  isVisible: false,
};

const CanvasContext = createContext<CanvasContextValue | undefined>(undefined);

export function CanvasProvider({ children }: { children: ReactNode }) {
  const [canvas, setCanvas] = useState<CanvasState>(defaultCanvas);

  const loadCanvas = useCallback((type: CanvasType, data: CanvasData = {}, title: string = '') => {
    // Auto-generate title if not provided
    const canvasTitles: Record<string, string> = {
      document_viewer: 'Document',
      document_list: 'Documents',
      document_search_results: 'Search Results',
      landing_page_viewer: 'Landing Pages',
      landing_page_details: 'Landing Page',
      campaign_viewer: 'Campaigns',
      contact_viewer: 'Contacts',
      analytics_dashboard: 'Analytics',
      task_progress: 'Task Progress',
      integrations_manager: 'Integrations',
    };

    setCanvas({
      type,
      data,
      title: title || canvasTitles[type || ''] || 'Canvas',
      isVisible: true,
    });
  }, []);

  const closeCanvas = useCallback(() => {
    setCanvas(prev => ({
      ...prev,
      isVisible: false,
    }));
    // Clear canvas after animation
    setTimeout(() => {
      setCanvas(defaultCanvas);
    }, 300);
  }, []);

  const updateCanvasData = useCallback((data: Partial<CanvasData>) => {
    setCanvas(prev => ({
      ...prev,
      data: { ...prev.data, ...data },
    }));
  }, []);

  return (
    <CanvasContext.Provider
      value={{
        canvas,
        loadCanvas,
        closeCanvas,
        updateCanvasData,
        isCanvasVisible: canvas.isVisible,
      }}
    >
      {children}
    </CanvasContext.Provider>
  );
}

export function useCanvas() {
  const context = useContext(CanvasContext);
  if (!context) {
    throw new Error('useCanvas must be used within a CanvasProvider');
  }
  return context;
}

/**
 * Parse SSE canvas event and trigger canvas load
 */
export function parseCanvasEvent(event: { type: string; canvas?: string; canvas_data?: any }): {
  canvasType: CanvasType;
  canvasData: CanvasData;
} | null {
  if (event.type !== 'load_canvas' || !event.canvas) {
    return null;
  }

  // Map web canvas types to mobile canvas types
  const canvasTypeMap: Record<string, CanvasType> = {
    'document_viewer': 'document_viewer',
    'document_list': 'document_list',
    'document_search_results': 'document_search_results',
    'landing_page_viewer': 'landing_page_viewer',
    'landing_page_details': 'landing_page_details',
    'campaign_viewer': 'campaign_viewer',
    'email_campaign_viewer': 'campaign_viewer',
    'contact_viewer': 'contact_viewer',
    'analytics_dashboard': 'analytics_dashboard',
    'task_progress': 'task_progress',
    'parallel_tasks': 'task_progress',
    'integrations_manager': 'integrations_manager',
  };

  const canvasType = canvasTypeMap[event.canvas] || null;

  return {
    canvasType,
    canvasData: event.canvas_data || {},
  };
}
