import { AlertCircle, Pencil, TestTube2, Trash2, Github, RefreshCw, Calendar, Clock, Activity } from 'lucide-react';
import { Button } from './ui/button';
import { Badge } from './ui/badge';
import { Card } from './ui/card';

export function ConnectionDetails() {
  return (
    <div className="flex-1 bg-[#0A0E1A] overflow-auto">
      {/* Header with error banner */}
      <div className="border-b border-[#1E293B]">
        <div className="bg-red-500/10 border-l-4 border-red-500 px-6 py-3 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <AlertCircle className="w-5 h-5 text-red-500" />
            <span className="text-red-400">Connection test failed. Not connected to MCP server</span>
          </div>
          <button className="text-red-400 hover:text-red-300">
            <span className="text-xl">×</span>
          </button>
        </div>
      </div>

      {/* Main content */}
      <div className="p-8">
        {/* Page header */}
        <div className="flex items-start justify-between mb-8">
          <div className="flex items-center gap-4">
            <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-[#7C3AED] to-[#A78BFA] flex items-center justify-center">
              <Github className="w-6 h-6 text-white" />
            </div>
            <div>
              <h1 className="text-white mb-1">GitHub - NuvolaNetworks</h1>
              <p className="text-[#94A3B8]">Manage your GitHub integration connection</p>
            </div>
          </div>
          
          <div className="flex items-center gap-3">
            <Button variant="outline" className="bg-transparent border-[#1E293B] text-white hover:bg-[#1E293B]">
              <Pencil className="w-4 h-4 mr-2" />
              Edit
            </Button>
            <Button className="bg-[#22D3EE] hover:bg-[#22D3EE]/90 text-black">
              <TestTube2 className="w-4 h-4 mr-2" />
              Test Connection
            </Button>
            <Button variant="destructive" className="bg-red-500/10 text-red-400 hover:bg-red-500/20 border border-red-500/20">
              <Trash2 className="w-4 h-4 mr-2" />
              Delete
            </Button>
          </div>
        </div>

        {/* Cards Grid */}
        <div className="grid grid-cols-2 gap-6 mb-8">
          {/* Connection Details Card */}
          <Card className="bg-[#1A1F35] border-[#1E293B] p-6">
            <h3 className="text-white mb-6">Connection Details</h3>
            <div className="space-y-4">
              <div className="flex items-center justify-between py-3 border-b border-[#1E293B]/50">
                <span className="text-[#94A3B8]">Type</span>
                <Badge className="bg-[#2D3548] text-white border-0">GITHUB</Badge>
              </div>
              <div className="flex items-center justify-between py-3 border-b border-[#1E293B]/50">
                <span className="text-[#94A3B8]">Status</span>
                <Badge className="bg-red-500/10 text-red-400 border border-red-500/20">OFFLINE</Badge>
              </div>
              <div className="flex items-center justify-between py-3 border-b border-[#1E293B]/50">
                <div className="flex items-center gap-2 text-[#94A3B8]">
                  <Calendar className="w-4 h-4" />
                  <span>Created</span>
                </div>
                <span className="text-white">October 30, 2025 00:33</span>
              </div>
              <div className="flex items-center justify-between py-3 border-b border-[#1E293B]/50">
                <div className="flex items-center gap-2 text-[#94A3B8]">
                  <RefreshCw className="w-4 h-4" />
                  <span>Last Sync</span>
                </div>
                <span className="text-white">Never</span>
              </div>
              <div className="flex items-center justify-between py-3 border-b border-[#1E293B]/50">
                <div className="flex items-center gap-2 text-[#94A3B8]">
                  <Clock className="w-4 h-4" />
                  <span>Last Health Check</span>
                </div>
                <span className="text-white">less than a minute ago</span>
              </div>
              <div className="flex items-center justify-between py-3">
                <div className="flex items-center gap-2 text-[#94A3B8]">
                  <Activity className="w-4 h-4" />
                  <span>Executions</span>
                </div>
                <span className="text-white">0</span>
              </div>
            </div>
          </Card>

          {/* Metadata Card */}
          <Card className="bg-[#1A1F35] border-[#1E293B] p-6">
            <h3 className="text-white mb-6">Error Metadata</h3>
            <div className="bg-[#0A0E1A] rounded-lg p-4 border border-[#1E293B]">
              <pre className="text-[#94A3B8] text-sm overflow-x-auto">
{`{
  "last_error": "Not connected to MCP server",
  "configured_at": "2025-10-30T00:33:11Z",
  "auth_method": "oauth",
  "last_error_at": "2025-10-30T21:36:48Z"
}`}
              </pre>
            </div>
          </Card>
        </div>

        {/* Recent Pipeline Executions */}
        <Card className="bg-[#1A1F35] border-[#1E293B] p-6">
          <div className="flex items-center justify-between mb-6">
            <h3 className="text-white">Recent Pipeline Executions</h3>
            <Button variant="outline" size="sm" className="bg-transparent border-[#1E293B] text-white hover:bg-[#1E293B]">
              View All
            </Button>
          </div>
          
          {/* Empty state */}
          <div className="flex flex-col items-center justify-center py-16">
            <div className="w-16 h-16 rounded-full bg-[#2D3548] flex items-center justify-center mb-4">
              <Activity className="w-8 h-8 text-[#94A3B8]" />
            </div>
            <p className="text-[#94A3B8]">No executions yet</p>
            <p className="text-[#64748B] mt-1">Pipeline executions will appear here once you start using this connection</p>
          </div>
        </Card>
      </div>
    </div>
  );
}
