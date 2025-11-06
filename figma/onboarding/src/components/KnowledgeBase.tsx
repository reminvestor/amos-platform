import { FileText, Upload, CheckCircle, Clock, XCircle, MessageSquare, ExternalLink } from 'lucide-react';
import { Button } from './ui/button';
import { Card } from './ui/card';

export function KnowledgeBase() {
  const stats = [
    { 
      label: 'Total Documents', 
      value: '0',
      icon: <FileText className="w-5 h-5" />,
      color: 'bg-blue-500/10 border-blue-500/20 text-blue-400'
    },
    { 
      label: 'Processed', 
      value: '0',
      icon: <CheckCircle className="w-5 h-5" />,
      color: 'bg-emerald-500/10 border-emerald-500/20 text-emerald-400'
    },
    { 
      label: 'Processing', 
      value: '0',
      icon: <Clock className="w-5 h-5" />,
      color: 'bg-amber-500/10 border-amber-500/20 text-amber-400'
    },
    { 
      label: 'Failed', 
      value: '0',
      icon: <XCircle className="w-5 h-5" />,
      color: 'bg-red-500/10 border-red-500/20 text-red-400'
    },
  ];

  return (
    <div className="flex-1 bg-[#0A0E1A] overflow-auto">
      {/* Header */}
      <div className="border-b border-[#1E293B] px-8 py-6 flex items-center justify-between">
        <div>
          <div className="flex items-center gap-3 mb-2">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#7C3AED] to-[#A78BFA] flex items-center justify-center">
              <BookOpen className="w-5 h-5 text-white" />
            </div>
            <h1 className="text-white">Knowledge Base</h1>
          </div>
          <p className="text-[#94A3B8] ml-[52px]">Documents uploaded to your knowledge base</p>
        </div>
        
        <Button 
          variant="outline" 
          className="bg-transparent border-[#1E293B] text-white hover:bg-[#1E293B] gap-2"
        >
          <MessageSquare className="w-4 h-4" />
          Chat Mode
        </Button>
      </div>

      {/* Main content */}
      <div className="p-8">
        {/* Upload button */}
        <div className="mb-6">
          <Button 
            className="bg-[#7C3AED] hover:bg-[#7C3AED]/90 text-white gap-2"
          >
            <Upload className="w-4 h-4" />
            Upload via Scout
          </Button>
        </div>

        {/* Stats Cards */}
        <div className="grid grid-cols-4 gap-4 mb-8">
          {stats.map((stat, index) => (
            <Card 
              key={index}
              className={`bg-[#1A1F35] border p-5 ${stat.color.split(' ').slice(1).join(' ')}`}
            >
              <div className="flex items-center justify-between mb-3">
                <div className={`w-10 h-10 rounded-lg ${stat.color.split(' ')[0]} flex items-center justify-center`}>
                  {stat.icon}
                </div>
              </div>
              <div className="space-y-1">
                <div className={`text-3xl ${stat.color.split(' ')[2]}`}>
                  {stat.value}
                </div>
                <div className="text-[#94A3B8] text-sm">{stat.label}</div>
              </div>
            </Card>
          ))}
        </div>

        {/* Empty State */}
        <Card className="bg-[#1A1F35] border-[#1E293B] p-12">
          <div className="flex flex-col items-center justify-center text-center">
            {/* Document Icon */}
            <div className="w-20 h-20 rounded-full bg-[#2D3548] flex items-center justify-center mb-6">
              <FileText className="w-10 h-10 text-[#94A3B8]" />
            </div>
            
            <p className="text-[#94A3B8] mb-6 max-w-md">
              Upload documents via Scout chat to add them to your knowledge base
            </p>
            
            <Button 
              className="bg-[#22D3EE] hover:bg-[#22D3EE]/90 text-black gap-2"
            >
              <MessageSquare className="w-4 h-4" />
              Go to Scout
              <ExternalLink className="w-4 h-4" />
            </Button>
          </div>
        </Card>
      </div>
    </div>
  );
}

function BookOpen({ className }: { className?: string }) {
  return (
    <svg className={className} fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
    </svg>
  );
}
