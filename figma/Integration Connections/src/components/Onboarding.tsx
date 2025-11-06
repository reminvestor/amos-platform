import { 
  Sparkles,
  MessageCircle,
  Send,
  Lightbulb,
  Zap,
  FileText,
  TrendingUp,
  Target
} from 'lucide-react';
import { Card } from './ui/card';
import { Button } from './ui/button';
import { useState } from 'react';

interface Message {
  role: 'assistant' | 'user';
  content: string;
}

export function Onboarding() {
  const [input, setInput] = useState('');
  const [messages, setMessages] = useState<Message[]>([
    {
      role: 'assistant',
      content: "Hi Ryan! I'm Scout, your AI marketing agent.\n\nGreat news! Your Starter plan 7-day trial has started successfully. You won't be charged until November 12, 2025.\n\nI see you're working with Martin Enterprises – that's exciting! I'm here to learn more about your business so I can help you succeed across all marketing channels. This will only take a few minutes, and I promise to make it painless – no boring forms!\n\nSince I already know your business name, let's dive deeper: What industry is Martin Enterprises in? Are you in tech, retail, healthcare, consulting, or something else?"
    }
  ]);

  const handleSend = () => {
    if (input.trim()) {
      setMessages([...messages, { role: 'user', content: input }]);
      setInput('');
    }
  };

  const features = [
    {
      icon: <MessageCircle className="w-5 h-5" />,
      title: 'Conversational Learning',
      description: 'AMOS learns about your business through natural conversation. Just chat! I\'ll ask you questions and get smarter with every response.',
      iconBg: 'bg-cyan-500/10',
      iconColor: 'text-cyan-400'
    },
    {
      icon: <Zap className="w-5 h-5" />,
      title: 'Intelligent Adaptation',
      description: 'The more AMOS knows about your business, the better recommendations and content it can create.',
      iconBg: 'bg-purple-500/10',
      iconColor: 'text-purple-400'
    },
    {
      icon: <FileText className="w-5 h-5" />,
      title: 'Instant Marketing Materials',
      description: 'Once AMOS understands your business, it can create landing pages, emails, and campaigns in seconds.',
      iconBg: 'bg-emerald-500/10',
      iconColor: 'text-emerald-400'
    },
    {
      icon: <TrendingUp className="w-5 h-5" />,
      title: 'Continuous Optimization',
      description: 'AMOS analyzes performance and suggests improvements to help your marketing efforts succeed.',
      iconBg: 'bg-amber-500/10',
      iconColor: 'text-amber-400'
    }
  ];

  return (
    <div className="w-full h-screen bg-[#0A0E1A] overflow-auto flex">
      {/* Left Info Panel */}
      <div className="w-80 bg-[#0F172A] border-r border-[#1E293B] p-6 overflow-y-auto">
        <div className="mb-8">
          <div className="flex items-center gap-3 mb-3">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#7C3AED] to-[#A78BFA] flex items-center justify-center">
              <Sparkles className="w-5 h-5 text-white" />
            </div>
            <h2 className="text-white">Getting Started</h2>
          </div>
          <p className="text-[#94A3B8] text-sm">Getting AMOS acquainted with your business</p>
        </div>

        <div className="space-y-6">
          <div>
            <h3 className="text-white mb-3 flex items-center gap-2">
              <Target className="w-4 h-4 text-[#7C3AED]" />
              Meet AMOS
            </h3>
            <p className="text-[#94A3B8] text-sm mb-4">Your AI Business Automation Assistant</p>
          </div>

          {features.map((feature, index) => (
            <div key={index} className="space-y-2">
              <div className="flex items-center gap-2">
                <div className={`w-8 h-8 rounded-lg ${feature.iconBg} flex items-center justify-center`}>
                  <div className={feature.iconColor}>
                    {feature.icon}
                  </div>
                </div>
                <h4 className="text-white text-sm">{feature.title}</h4>
              </div>
              <p className="text-[#94A3B8] text-xs leading-relaxed">{feature.description}</p>
            </div>
          ))}

          <Card className="bg-[#1A1F35] border-[#1E293B] p-4">
            <div className="flex items-start gap-3">
              <div className="w-8 h-8 rounded-lg bg-blue-500/10 flex items-center justify-center flex-shrink-0">
                <Lightbulb className="w-4 h-4 text-blue-400" />
              </div>
              <div>
                <h4 className="text-white text-sm mb-1">Pro Tips</h4>
                <p className="text-[#94A3B8] text-xs leading-relaxed">
                  Share your industry, target audience, and what makes your business unique.
                </p>
              </div>
            </div>
          </Card>
        </div>
      </div>

      {/* Main Chat Area */}
      <div className="flex-1 flex flex-col">
        {/* Header */}
        <div className="border-b border-[#1E293B] px-8 py-6">
          <h1 className="text-white mb-2">Welcome to Amos! 🎉</h1>
          <p className="text-[#94A3B8]">Let's get AMOS acquainted with your business</p>
        </div>

        {/* Messages */}
        <div className="flex-1 overflow-y-auto p-8">
          <div className="max-w-4xl mx-auto space-y-6">
            {messages.map((message, index) => (
              <div key={index} className={`flex gap-4 ${message.role === 'user' ? 'justify-end' : 'justify-start'}`}>
                {message.role === 'assistant' && (
                  <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#7C3AED] to-[#A78BFA] flex items-center justify-center flex-shrink-0">
                    <Sparkles className="w-5 h-5 text-white" />
                  </div>
                )}
                <div className={`flex-1 max-w-2xl ${message.role === 'user' ? 'ml-auto' : ''}`}>
                  {message.role === 'assistant' && (
                    <div className="text-[#7C3AED] mb-2 text-sm">AMOS</div>
                  )}
                  <Card className={`p-6 ${
                    message.role === 'assistant' 
                      ? 'bg-[#1A1F35] border-[#1E293B]' 
                      : 'bg-[#7C3AED]/10 border-[#7C3AED]/20'
                  }`}>
                    <p className="text-white whitespace-pre-line leading-relaxed">{message.content}</p>
                  </Card>
                </div>
                {message.role === 'user' && (
                  <div className="w-10 h-10 rounded-xl bg-[#1E293B] flex items-center justify-center flex-shrink-0">
                    <span className="text-white">RM</span>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>

        {/* Input */}
        <div className="border-t border-[#1E293B] p-6">
          <div className="max-w-4xl mx-auto">
            <div className="flex gap-3">
              <input
                type="text"
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && handleSend()}
                placeholder="Tell AMOS about your business and industry goals, challenges..."
                className="flex-1 bg-[#1A1F35] border border-[#1E293B] rounded-lg px-4 py-3 text-white placeholder:text-[#64748B] focus:outline-none focus:ring-2 focus:ring-[#7C3AED] focus:border-transparent"
              />
              <Button 
                onClick={handleSend}
                className="bg-[#7C3AED] hover:bg-[#7C3AED]/90 text-white px-6"
              >
                <Send className="w-4 h-4" />
              </Button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
