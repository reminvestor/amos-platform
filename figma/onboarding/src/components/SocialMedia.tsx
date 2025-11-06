import { 
  Share2,
  Plus,
  Calendar,
  TrendingUp
} from 'lucide-react';
import { Card } from './ui/card';
import { Button } from './ui/button';

export function SocialMedia() {
  return (
    <div className="flex-1 bg-[#0A0E1A] overflow-auto">
      {/* Header */}
      <div className="border-b border-[#1E293B] px-8 py-6">
        <div className="flex items-center justify-between">
          <div>
            <div className="flex items-center gap-3 mb-2">
              <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#7C3AED] to-[#A78BFA] flex items-center justify-center">
                <Share2 className="w-5 h-5 text-white" />
              </div>
              <h1 className="text-white">Social Media Posts</h1>
            </div>
            <p className="text-[#94A3B8] ml-[52px]">Manage and schedule your social media content</p>
          </div>
          
          <Button 
            className="bg-[#7C3AED] hover:bg-[#7C3AED]/90 text-white gap-2"
          >
            <Plus className="w-4 h-4" />
            New Post
          </Button>
        </div>
      </div>

      {/* Main content */}
      <div className="p-8">
        {/* Stats Cards */}
        <div className="grid grid-cols-3 gap-6 mb-8">
          <Card className="bg-[#1A1F35] border-[#1E293B] p-6 hover:border-[#2D3548] transition-colors">
            <div className="flex items-start justify-between mb-4">
              <div className="w-12 h-12 rounded-xl bg-purple-500/10 flex items-center justify-center">
                <Share2 className="w-6 h-6 text-purple-400" />
              </div>
            </div>
            <div className="space-y-1">
              <div className="text-3xl text-white">0</div>
              <div className="text-[#94A3B8]">Total Posts</div>
            </div>
          </Card>

          <Card className="bg-[#1A1F35] border-[#1E293B] p-6 hover:border-[#2D3548] transition-colors">
            <div className="flex items-start justify-between mb-4">
              <div className="w-12 h-12 rounded-xl bg-cyan-500/10 flex items-center justify-center">
                <Calendar className="w-6 h-6 text-cyan-400" />
              </div>
            </div>
            <div className="space-y-1">
              <div className="text-3xl text-white">0</div>
              <div className="text-[#94A3B8]">Scheduled</div>
            </div>
          </Card>

          <Card className="bg-[#1A1F35] border-[#1E293B] p-6 hover:border-[#2D3548] transition-colors">
            <div className="flex items-start justify-between mb-4">
              <div className="w-12 h-12 rounded-xl bg-emerald-500/10 flex items-center justify-center">
                <TrendingUp className="w-6 h-6 text-emerald-400" />
              </div>
            </div>
            <div className="space-y-1">
              <div className="text-3xl text-white">0</div>
              <div className="text-[#94A3B8]">Published</div>
            </div>
          </Card>
        </div>

        {/* Empty State */}
        <Card className="bg-[#1A1F35] border-[#1E293B] p-12">
          <div className="flex flex-col items-center justify-center text-center">
            {/* Icon */}
            <div className="w-20 h-20 rounded-full bg-[#2D3548] flex items-center justify-center mb-6">
              <Share2 className="w-10 h-10 text-[#94A3B8]" />
            </div>
            
            <h2 className="text-white mb-2">No Social Posts Yet</h2>
            <p className="text-[#94A3B8] mb-6 max-w-md">
              Create your first social media post and start engaging with your audience
            </p>
            
            <Button 
              className="bg-[#7C3AED] hover:bg-[#7C3AED]/90 text-white gap-2"
            >
              <Plus className="w-4 h-4" />
              Create Your First Post
            </Button>
          </div>
        </Card>
      </div>
    </div>
  );
}
