import { 
  MessageSquare, 
  MessageCircle, 
  Coins, 
  DollarSign, 
  PlayCircle, 
  CheckCircle, 
  XCircle, 
  Link2, 
  Zap, 
  AlertCircle,
  FileText,
  Send,
  FilePlus,
  BarChart3
} from 'lucide-react';
import { Card } from './ui/card';
import { Button } from './ui/button';

interface MetricCardProps {
  label: string;
  value: string | number;
  icon: React.ReactNode;
  iconBg: string;
  iconColor: string;
}

function MetricCard({ label, value, icon, iconBg, iconColor }: MetricCardProps) {
  return (
    <Card className="bg-[#1A1F35] border-[#1E293B] p-6 hover:border-[#2D3548] transition-colors">
      <div className="flex items-start justify-between mb-4">
        <div className={`w-12 h-12 rounded-xl ${iconBg} flex items-center justify-center`}>
          <div className={iconColor}>
            {icon}
          </div>
        </div>
        <div className="text-right">
          <div className="text-3xl text-white mb-1">{value}</div>
        </div>
      </div>
      <div className="text-[#94A3B8]">{label}</div>
    </Card>
  );
}

export function ObservabilityAnalytics() {
  const aiUsageMetrics = [
    {
      label: 'Conversations',
      value: 0,
      icon: <MessageSquare className="w-6 h-6" />,
      iconBg: 'bg-purple-500/10',
      iconColor: 'text-purple-400'
    },
    {
      label: 'Messages',
      value: 5,
      icon: <MessageCircle className="w-6 h-6" />,
      iconBg: 'bg-cyan-500/10',
      iconColor: 'text-cyan-400'
    },
    {
      label: 'Est. Tokens',
      value: '2,500',
      icon: <Coins className="w-6 h-6" />,
      iconBg: 'bg-amber-500/10',
      iconColor: 'text-amber-400'
    },
    {
      label: 'Est. Cost',
      value: '$0.05',
      icon: <DollarSign className="w-6 h-6" />,
      iconBg: 'bg-emerald-500/10',
      iconColor: 'text-emerald-400'
    },
  ];

  const workflowsMetrics = [
    {
      label: 'Started',
      value: 0,
      icon: <PlayCircle className="w-6 h-6" />,
      iconBg: 'bg-slate-500/10',
      iconColor: 'text-slate-400'
    },
    {
      label: 'Completed',
      value: 0,
      icon: <CheckCircle className="w-6 h-6" />,
      iconBg: 'bg-emerald-500/10',
      iconColor: 'text-emerald-400'
    },
    {
      label: 'Failed',
      value: 0,
      icon: <XCircle className="w-6 h-6" />,
      iconBg: 'bg-red-500/10',
      iconColor: 'text-red-400'
    },
  ];

  const integrationsMetrics = [
    {
      label: 'Active Connections',
      value: 0,
      icon: <Link2 className="w-6 h-6" />,
      iconBg: 'bg-slate-500/10',
      iconColor: 'text-slate-400'
    },
    {
      label: 'API Calls',
      value: 0,
      icon: <Zap className="w-6 h-6" />,
      iconBg: 'bg-emerald-500/10',
      iconColor: 'text-emerald-400'
    },
    {
      label: 'Failed Calls',
      value: 0,
      icon: <AlertCircle className="w-6 h-6" />,
      iconBg: 'bg-red-500/10',
      iconColor: 'text-red-400'
    },
  ];

  const campaignsMetrics = [
    {
      label: 'Total',
      value: 0,
      icon: <FileText className="w-6 h-6" />,
      iconBg: 'bg-slate-500/10',
      iconColor: 'text-slate-400'
    },
    {
      label: 'Sent',
      value: 0,
      icon: <Send className="w-6 h-6" />,
      iconBg: 'bg-cyan-500/10',
      iconColor: 'text-cyan-400'
    },
    {
      label: 'Drafts',
      value: 0,
      icon: <FilePlus className="w-6 h-6" />,
      iconBg: 'bg-amber-500/10',
      iconColor: 'text-amber-400'
    },
  ];

  return (
    <div className="flex-1 bg-[#0A0E1A] overflow-auto">
      {/* Header */}
      <div className="border-b border-[#1E293B] px-8 py-6">
        <div className="flex items-center gap-3 mb-2">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#7C3AED] to-[#A78BFA] flex items-center justify-center">
            <BarChart3 className="w-5 h-5 text-white" />
          </div>
          <h1 className="text-white">Observability & Analytics</h1>
        </div>
        <p className="text-[#94A3B8] ml-[52px]">Track your entity's AI usage, workflows, and performance</p>
      </div>

      {/* Main content */}
      <div className="p-8">
        {/* Time filters */}
        <div className="flex items-center gap-3 mb-8">
          <Button 
            size="sm"
            className="bg-[#7C3AED] text-white hover:bg-[#7C3AED]/90"
          >
            Today
          </Button>
          <Button 
            size="sm"
            variant="outline"
            className="bg-transparent border-[#1E293B] text-[#94A3B8] hover:bg-[#1E293B] hover:text-white"
          >
            7 Days
          </Button>
          <Button 
            size="sm"
            variant="outline"
            className="bg-transparent border-[#1E293B] text-[#94A3B8] hover:bg-[#1E293B] hover:text-white"
          >
            30 Days
          </Button>
        </div>

        {/* AI Usage Section */}
        <div className="mb-8">
          <h2 className="text-white mb-4 flex items-center gap-2">
            <MessageSquare className="w-5 h-5 text-[#7C3AED]" />
            AI Usage
          </h2>
          <div className="grid grid-cols-4 gap-6">
            {aiUsageMetrics.map((metric, index) => (
              <MetricCard
                key={index}
                label={metric.label}
                value={metric.value}
                icon={metric.icon}
                iconBg={metric.iconBg}
                iconColor={metric.iconColor}
              />
            ))}
          </div>
        </div>

        {/* Workflows Section */}
        <div className="mb-8">
          <h2 className="text-white mb-4 flex items-center gap-2">
            <PlayCircle className="w-5 h-5 text-[#7C3AED]" />
            Workflows
          </h2>
          <div className="grid grid-cols-4 gap-6">
            {workflowsMetrics.map((metric, index) => (
              <MetricCard
                key={index}
                label={metric.label}
                value={metric.value}
                icon={metric.icon}
                iconBg={metric.iconBg}
                iconColor={metric.iconColor}
              />
            ))}
          </div>
        </div>

        {/* Integrations Section */}
        <div className="mb-8">
          <h2 className="text-white mb-4 flex items-center gap-2">
            <Link2 className="w-5 h-5 text-[#7C3AED]" />
            Integrations
          </h2>
          <div className="grid grid-cols-4 gap-6">
            {integrationsMetrics.map((metric, index) => (
              <MetricCard
                key={index}
                label={metric.label}
                value={metric.value}
                icon={metric.icon}
                iconBg={metric.iconBg}
                iconColor={metric.iconColor}
              />
            ))}
          </div>
        </div>

        {/* Campaigns Section */}
        <div>
          <h2 className="text-white mb-4 flex items-center gap-2">
            <FileText className="w-5 h-5 text-[#7C3AED]" />
            Campaigns
          </h2>
          <div className="grid grid-cols-4 gap-6">
            {campaignsMetrics.map((metric, index) => (
              <MetricCard
                key={index}
                label={metric.label}
                value={metric.value}
                icon={metric.icon}
                iconBg={metric.iconBg}
                iconColor={metric.iconColor}
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
