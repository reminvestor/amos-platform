import { 
  Search,
  Slack,
  CheckCircle2,
  Plus,
  Settings,
  MessageSquare,
  FileSpreadsheet,
  Code,
  CreditCard,
  ShoppingBag,
  Megaphone
} from 'lucide-react';
import { Card } from './ui/card';
import { Button } from './ui/button';
import { Input } from './ui/input';
import { Badge } from './ui/badge';
import { useState } from 'react';

interface Integration {
  id: string;
  name: string;
  description: string;
  category: string;
  icon: React.ReactNode;
  connected: boolean;
  capabilities?: string[];
  verified?: boolean;
}

export function Connections() {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string>('all');

  const integrations: Integration[] = [
    {
      id: 'slack',
      name: 'Slack',
      description: 'Communicate, manage ideas, and organize project information and tasks collaboratively.',
      category: 'Communication',
      icon: <Slack className="w-6 h-6" />,
      connected: true,
      capabilities: ['Send messages', 'Get notifications'],
      verified: true
    },
    {
      id: 'google-drive',
      name: 'Google Drive',
      description: 'Store, sync, and share files across all devices. Access your files anywhere.',
      category: 'Productivity',
      icon: <FileSpreadsheet className="w-6 h-6" />,
      connected: false,
      capabilities: ['File storage', 'Real-time collaboration']
    },
    {
      id: 'google-sheets',
      name: 'Google Sheets',
      description: 'Create and edit spreadsheets, analyze data, and collaborate in real-time.',
      category: 'Productivity',
      icon: <FileSpreadsheet className="w-6 h-6" />,
      connected: false,
      capabilities: ['Data analysis', 'Collaboration']
    },
    {
      id: 'hubspot',
      name: 'HubSpot',
      description: 'Complete CRM platform for sales, marketing, and customer service teams.',
      category: 'CMS',
      icon: <Code className="w-6 h-6" />,
      connected: false,
      capabilities: ['CRM', 'Marketing automation']
    },
    {
      id: 'convertwithonline',
      name: 'ConvertWith.Online',
      description: 'Accounting software for invoicing, accounting, payroll and more.',
      category: 'Payment',
      icon: <CreditCard className="w-6 h-6" />,
      connected: false,
      capabilities: ['Invoicing', 'Payment processing']
    },
    {
      id: 'stripe',
      name: 'Stripe',
      description: 'Accept payments and manage billing for your business.',
      category: 'Payment',
      icon: <CreditCard className="w-6 h-6" />,
      connected: true,
      capabilities: ['Payment processing', 'Manage transactions'],
      verified: true
    },
    {
      id: 'shopify',
      name: 'Shopify',
      description: 'Manage your online store, process orders, inventory, and payments.',
      category: 'Ecommerce',
      icon: <ShoppingBag className="w-6 h-6" />,
      connected: false,
      capabilities: ['Online store', 'Inventory management']
    }
  ];

  const categories = [
    { id: 'all', label: 'All Integrations', count: integrations.length },
    { id: 'Communication', label: 'Communication', count: integrations.filter(i => i.category === 'Communication').length },
    { id: 'Productivity', label: 'Productivity', count: integrations.filter(i => i.category === 'Productivity').length },
    { id: 'CMS', label: 'CMS', count: integrations.filter(i => i.category === 'CMS').length },
    { id: 'Payment', label: 'Payment', count: integrations.filter(i => i.category === 'Payment').length },
    { id: 'Ecommerce', label: 'Ecommerce', count: integrations.filter(i => i.category === 'Ecommerce').length }
  ];

  const filteredIntegrations = integrations.filter(integration => {
    const matchesSearch = integration.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         integration.description.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesCategory = selectedCategory === 'all' || integration.category === selectedCategory;
    return matchesSearch && matchesCategory;
  });

  const groupedIntegrations = filteredIntegrations.reduce((acc, integration) => {
    if (!acc[integration.category]) {
      acc[integration.category] = [];
    }
    acc[integration.category].push(integration);
    return acc;
  }, {} as Record<string, Integration[]>);

  return (
    <div className="flex-1 bg-[#0A0E1A] overflow-auto">
      <div className="p-8">
        {/* Header */}
        <div className="mb-8">
          <h1 className="text-white mb-2">Integration Connections</h1>
          <p className="text-[#94A3B8]">Manage your platform connections</p>
        </div>

        {/* Search and Stats */}
        <div className="mb-8">
          <div className="relative mb-6">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-[#64748B] w-5 h-5" />
            <Input
              type="text"
              placeholder="Search integrations..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-10 bg-[#1A1F35] border-[#1E293B] text-white placeholder:text-[#64748B] focus:ring-2 focus:ring-[#7C3AED] focus:border-transparent"
            />
          </div>

          {/* Stats Cards */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
            <Card className="bg-gradient-to-br from-[#7C3AED]/20 to-[#7C3AED]/5 border-[#7C3AED]/30 p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-[#94A3B8] text-sm mb-1">Total Integrations</p>
                  <p className="text-white">{integrations.length}</p>
                </div>
                <div className="w-10 h-10 rounded-lg bg-[#7C3AED]/20 flex items-center justify-center">
                  <Plus className="w-5 h-5 text-[#7C3AED]" />
                </div>
              </div>
            </Card>

            <Card className="bg-gradient-to-br from-emerald-500/20 to-emerald-500/5 border-emerald-500/30 p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-[#94A3B8] text-sm mb-1">Connected</p>
                  <p className="text-white">{integrations.filter(i => i.connected).length}</p>
                </div>
                <div className="w-10 h-10 rounded-lg bg-emerald-500/20 flex items-center justify-center">
                  <CheckCircle2 className="w-5 h-5 text-emerald-400" />
                </div>
              </div>
            </Card>

            <Card className="bg-gradient-to-br from-amber-500/20 to-amber-500/5 border-amber-500/30 p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-[#94A3B8] text-sm mb-1">Available</p>
                  <p className="text-white">{integrations.filter(i => !i.connected).length}</p>
                </div>
                <div className="w-10 h-10 rounded-lg bg-amber-500/20 flex items-center justify-center">
                  <Megaphone className="w-5 h-5 text-amber-400" />
                </div>
              </div>
            </Card>
          </div>

          {/* Category Filters */}
          <div className="flex flex-wrap gap-2">
            {categories.map(category => (
              <Button
                key={category.id}
                variant="ghost"
                size="sm"
                onClick={() => setSelectedCategory(category.id)}
                className={`${
                  selectedCategory === category.id
                    ? 'bg-[#7C3AED] text-white hover:bg-[#7C3AED]/90'
                    : 'bg-[#1A1F35] text-[#94A3B8] hover:text-white hover:bg-[#1E293B]'
                } border border-[#1E293B]`}
              >
                {category.label}
                <Badge variant="secondary" className="ml-2 bg-[#0F172A] text-[#94A3B8] border-none">
                  {category.count}
                </Badge>
              </Button>
            ))}
          </div>
        </div>

        {/* Integration Cards by Category */}
        {Object.entries(groupedIntegrations).map(([category, items]) => (
          <div key={category} className="mb-8">
            <h2 className="text-white mb-4">{category}</h2>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              {items.map(integration => (
                <Card key={integration.id} className="bg-[#1A1F35] border-[#1E293B] p-6 hover:border-[#7C3AED]/50 transition-all">
                  <div className="flex items-start justify-between mb-4">
                    <div className="flex items-center gap-3">
                      <div className={`w-12 h-12 rounded-lg flex items-center justify-center ${
                        integration.connected 
                          ? 'bg-emerald-500/10 text-emerald-400' 
                          : 'bg-[#0F172A] text-[#94A3B8]'
                      }`}>
                        {integration.icon}
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <h3 className="text-white">{integration.name}</h3>
                          {integration.verified && (
                            <CheckCircle2 className="w-4 h-4 text-blue-400" />
                          )}
                        </div>
                        {integration.connected && (
                          <Badge variant="secondary" className="bg-emerald-500/10 text-emerald-400 border-emerald-500/20 mt-1">
                            Connected
                          </Badge>
                        )}
                      </div>
                    </div>
                    <Button
                      size="sm"
                      variant="ghost"
                      className="text-[#94A3B8] hover:text-white hover:bg-[#1E293B]"
                    >
                      <Settings className="w-4 h-4" />
                    </Button>
                  </div>

                  <p className="text-[#94A3B8] text-sm mb-4 leading-relaxed">
                    {integration.description}
                  </p>

                  {integration.capabilities && (
                    <div className="flex flex-wrap gap-2 mb-4">
                      {integration.capabilities.map((capability, index) => (
                        <Badge key={index} variant="secondary" className="bg-[#0F172A] text-[#94A3B8] border-[#1E293B]">
                          {capability}
                        </Badge>
                      ))}
                    </div>
                  )}

                  <Button 
                    className={`w-full ${
                      integration.connected
                        ? 'bg-[#1E293B] hover:bg-[#1E293B]/80 text-white'
                        : 'bg-[#7C3AED] hover:bg-[#7C3AED]/90 text-white'
                    }`}
                  >
                    {integration.connected ? 'Configure' : 'Connect'}
                  </Button>
                </Card>
              ))}
            </div>
          </div>
        ))}

        {filteredIntegrations.length === 0 && (
          <Card className="bg-[#1A1F35] border-[#1E293B] p-12 text-center">
            <div className="w-16 h-16 rounded-full bg-[#0F172A] flex items-center justify-center mx-auto mb-4">
              <Search className="w-8 h-8 text-[#64748B]" />
            </div>
            <h3 className="text-white mb-2">No integrations found</h3>
            <p className="text-[#94A3B8]">
              Try adjusting your search or filter to find what you're looking for
            </p>
          </Card>
        )}
      </div>
    </div>
  );
}
