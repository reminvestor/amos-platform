import { 
  Lock,
  Info,
  Shield
} from 'lucide-react';
import { Card } from './ui/card';
import { Button } from './ui/button';

export function PrivacyControls() {
  return (
    <div className="flex-1 bg-[#0A0E1A] overflow-auto">
      {/* Header */}
      <div className="border-b border-[#1E293B] px-8 py-6">
        <div className="flex items-center gap-3 mb-2">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#7C3AED] to-[#A78BFA] flex items-center justify-center">
            <Lock className="w-5 h-5 text-white" />
          </div>
          <h1 className="text-white">Privacy & Data Controls</h1>
        </div>
        <p className="text-[#94A3B8] ml-[52px]">Control what data gets shared with AI and how it's used</p>
      </div>

      {/* Main content */}
      <div className="p-8 max-w-5xl">
        <div className="grid grid-cols-2 gap-6 mb-6">
          {/* Data Sharing with AI */}
          <Card className="bg-[#1A1F35] border-[#1E293B] p-6">
            <h3 className="text-white mb-6">Data Sharing with AI</h3>
            
            <div className="space-y-4">
              <label className="flex items-start gap-3 cursor-pointer group">
                <input 
                  type="checkbox" 
                  defaultChecked
                  className="mt-1 w-4 h-4 rounded border-[#1E293B] bg-[#0F172A] text-[#7C3AED] focus:ring-[#7C3AED] focus:ring-offset-0"
                />
                <div className="flex-1">
                  <div className="text-white mb-1">Share Business Profile</div>
                  <div className="text-[#94A3B8] text-sm">
                    Allow AI to access business name, industry, description
                  </div>
                </div>
              </label>

              <label className="flex items-start gap-3 cursor-pointer group">
                <input 
                  type="checkbox" 
                  className="mt-1 w-4 h-4 rounded border-[#1E293B] bg-[#0F172A] text-[#7C3AED] focus:ring-[#7C3AED] focus:ring-offset-0"
                />
                <div className="flex-1">
                  <div className="text-white mb-1">Share Contact Data</div>
                  <div className="text-[#94A3B8] text-sm">
                    Allow AI to access contact names, emails, etc.
                  </div>
                </div>
              </label>

              <label className="flex items-start gap-3 cursor-pointer group">
                <input 
                  type="checkbox" 
                  defaultChecked
                  className="mt-1 w-4 h-4 rounded border-[#1E293B] bg-[#0F172A] text-[#7C3AED] focus:ring-[#7C3AED] focus:ring-offset-0"
                />
                <div className="flex-1">
                  <div className="text-white mb-1">Share Campaign Metrics</div>
                  <div className="text-[#94A3B8] text-sm">
                    Allow AI to analyze campaign performance data
                  </div>
                </div>
              </label>

              <label className="flex items-start gap-3 cursor-pointer group">
                <input 
                  type="checkbox" 
                  defaultChecked
                  className="mt-1 w-4 h-4 rounded border-[#1E293B] bg-[#0F172A] text-[#7C3AED] focus:ring-[#7C3AED] focus:ring-offset-0"
                />
                <div className="flex-1">
                  <div className="text-white mb-1">Share Uploaded File Contents</div>
                  <div className="text-[#94A3B8] text-sm">
                    Allow AI to read uploaded documents and images
                  </div>
                </div>
              </label>
            </div>
          </Card>

          {/* PII Masking */}
          <Card className="bg-[#1A1F35] border-[#1E293B] p-6">
            <h3 className="text-white mb-6">PII Masking</h3>
            
            <div className="space-y-4">
              <label className="flex items-start gap-3 cursor-pointer group">
                <input 
                  type="checkbox" 
                  defaultChecked
                  className="mt-1 w-4 h-4 rounded border-[#1E293B] bg-[#0F172A] text-[#7C3AED] focus:ring-[#7C3AED] focus:ring-offset-0"
                />
                <div className="flex-1">
                  <div className="text-white mb-1">Auto-mask Personally Identifiable Information</div>
                  <div className="text-[#94A3B8] text-sm">
                    Automatically detect and mask PII before sending to AI
                  </div>
                </div>
              </label>

              <label className="flex items-start gap-3 cursor-pointer group">
                <input 
                  type="checkbox" 
                  defaultChecked
                  className="mt-1 w-4 h-4 rounded border-[#1E293B] bg-[#0F172A] text-[#7C3AED] focus:ring-[#7C3AED] focus:ring-offset-0"
                />
                <div className="flex-1">
                  <div className="text-white mb-1">Mask Email Addresses</div>
                </div>
              </label>

              <label className="flex items-start gap-3 cursor-pointer group">
                <input 
                  type="checkbox" 
                  defaultChecked
                  className="mt-1 w-4 h-4 rounded border-[#1E293B] bg-[#0F172A] text-[#7C3AED] focus:ring-[#7C3AED] focus:ring-offset-0"
                />
                <div className="flex-1">
                  <div className="text-white mb-1">Mask Phone Numbers</div>
                </div>
              </label>

              <label className="flex items-start gap-3 cursor-pointer group">
                <input 
                  type="checkbox" 
                  defaultChecked
                  className="mt-1 w-4 h-4 rounded border-[#1E293B] bg-[#0F172A] text-[#7C3AED] focus:ring-[#7C3AED] focus:ring-offset-0"
                />
                <div className="flex-1">
                  <div className="text-white mb-1">Mask Physical Addresses</div>
                </div>
              </label>
            </div>
          </Card>
        </div>

        {/* Data Retention */}
        <Card className="bg-[#1A1F35] border-[#1E293B] p-6 mb-6">
          <h3 className="text-white mb-6">Data Retention</h3>
          
          <div className="space-y-4">
            <div>
              <label className="text-[#94A3B8] text-sm mb-2 block">
                Retain AI conversation data for:
              </label>
              <div className="flex items-center gap-3">
                <input 
                  type="text"
                  defaultValue="90 days"
                  className="w-32 bg-[#0F172A] border border-[#1E293B] rounded-lg px-3 py-2 text-white"
                />
              </div>
            </div>

            <div>
              <label className="text-[#94A3B8] text-sm mb-2 block">
                Allow Data Export
              </label>
              <p className="text-[#94A3B8] text-sm">
                Users can download their AI conversation history
              </p>
            </div>
          </div>
        </Card>

        {/* Save Button */}
        <div className="flex items-center gap-4">
          <Button 
            className="bg-[#7C3AED] hover:bg-[#7C3AED]/90 text-white"
          >
            Save Privacy Settings
          </Button>
          
          <div className="flex-1 bg-cyan-500/10 border border-cyan-500/20 rounded-lg px-4 py-3 flex items-start gap-3">
            <Info className="w-5 h-5 text-cyan-400 flex-shrink-0 mt-0.5" />
            <p className="text-cyan-400 text-sm">
              These settings control what data is shared with AI models. Changes take effect immediately.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
