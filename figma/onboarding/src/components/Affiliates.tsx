import { 
  DollarSign, 
  TrendingUp, 
  Megaphone,
  Users,
  Copy,
  Info,
  AlertCircle
} from 'lucide-react';
import { Card } from './ui/card';
import { Button } from './ui/button';
import { Badge } from './ui/badge';

interface InfoCardProps {
  icon: React.ReactNode;
  title: string;
  description: string;
  iconBg: string;
  iconColor: string;
}

function InfoCard({ icon, title, description, iconBg, iconColor }: InfoCardProps) {
  return (
    <Card className="bg-[#1A1F35] border-[#1E293B] p-6 hover:border-[#2D3548] transition-colors">
      <div className={`w-12 h-12 rounded-xl ${iconBg} flex items-center justify-center mb-4`}>
        <div className={iconColor}>
          {icon}
        </div>
      </div>
      <h3 className="text-white mb-2">{title}</h3>
      <p className="text-[#94A3B8] text-sm">{description}</p>
    </Card>
  );
}

export function Affiliates() {
  const infoCards = [
    {
      icon: <DollarSign className="w-6 h-6" />,
      title: 'Earn 20% recurring commissions for 12 months on all referrals',
      description: 'Get paid monthly for every customer you refer',
      iconBg: 'bg-emerald-500/10',
      iconColor: 'text-emerald-400'
    },
    {
      icon: <TrendingUp className="w-6 h-6" />,
      title: 'Unlock higher commission rates as you refer more customers',
      description: 'Scale your earnings with our tiered commission structure',
      iconBg: 'bg-purple-500/10',
      iconColor: 'text-purple-400'
    },
    {
      icon: <Megaphone className="w-6 h-6" />,
      title: 'Access banners, logos, and pre-written content to promote AMOS',
      description: 'Get all the marketing materials you need to succeed',
      iconBg: 'bg-cyan-500/10',
      iconColor: 'text-cyan-400'
    }
  ];

  const tiers = [
    { 
      tier: '1', 
      minReferrals: '0', 
      rate: '20%', 
      benefits: 'Standard marketing materials'
    },
    { 
      tier: '2', 
      minReferrals: '5', 
      rate: '25%', 
      benefits: 'Priority support and feature access'
    },
    { 
      tier: '3', 
      minReferrals: '10', 
      rate: '30%', 
      benefits: 'Dedicated account manager, co-marketing opportunities'
    }
  ];

  return (
    <div className="flex-1 bg-[#0A0E1A] overflow-auto">
      {/* Header */}
      <div className="border-b border-[#1E293B] px-8 py-6">
        <div className="flex items-center gap-3 mb-2">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#7C3AED] to-[#A78BFA] flex items-center justify-center">
            <Users className="w-5 h-5 text-white" />
          </div>
          <h1 className="text-white">Join Affiliates</h1>
        </div>
        <p className="text-[#94A3B8] ml-[52px]">
          Earn commissions by referring customers to AMOS and help others discover the power of AI-driven marketing automation
        </p>
      </div>

      {/* Main content */}
      <div className="p-8 max-w-6xl">
        {/* Info Cards */}
        <div className="grid grid-cols-3 gap-6 mb-8">
          {infoCards.map((card, index) => (
            <InfoCard
              key={index}
              icon={card.icon}
              title={card.title}
              description={card.description}
              iconBg={card.iconBg}
              iconColor={card.iconColor}
            />
          ))}
        </div>

        {/* Commission Tiers */}
        <Card className="bg-[#1A1F35] border-[#1E293B] p-6 mb-6">
          <div className="flex items-center gap-3 mb-6">
            <div className="w-10 h-10 rounded-xl bg-purple-500/10 flex items-center justify-center">
              <TrendingUp className="w-5 h-5 text-purple-400" />
            </div>
            <h2 className="text-white">Commission Tiers</h2>
          </div>

          <div className="overflow-hidden rounded-lg border border-[#1E293B]">
            <table className="w-full">
              <thead className="bg-[#0F172A]">
                <tr>
                  <th className="text-left px-6 py-3 text-[#94A3B8]">Tier</th>
                  <th className="text-left px-6 py-3 text-[#94A3B8]">Minimum Referrals</th>
                  <th className="text-left px-6 py-3 text-[#94A3B8]">Commission Rate</th>
                  <th className="text-left px-6 py-3 text-[#94A3B8]">Benefits</th>
                </tr>
              </thead>
              <tbody>
                {tiers.map((tier, index) => (
                  <tr 
                    key={index}
                    className="border-t border-[#1E293B] hover:bg-[#0F172A]/50 transition-colors"
                  >
                    <td className="px-6 py-4">
                      <Badge className="bg-purple-500/10 text-purple-400 border-0">
                        {tier.tier}
                      </Badge>
                    </td>
                    <td className="px-6 py-4 text-white">{tier.minReferrals}</td>
                    <td className="px-6 py-4 text-emerald-400">{tier.rate}</td>
                    <td className="px-6 py-4 text-[#94A3B8]">{tier.benefits}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>

        {/* Affiliate Link Section */}
        <Card className="bg-[#1A1F35] border-[#1E293B] p-6 mb-4">
          <h3 className="text-white mb-4">Your Affiliate Program Link</h3>
          <div className="bg-[#0F172A] rounded-lg p-4 border border-[#1E293B] mb-3">
            <code className="text-[#94A3B8] text-sm">
              https://amos.ai/affiliate/join
            </code>
          </div>
          <div className="flex items-start gap-2 text-sm text-[#94A3B8]">
            <Info className="w-4 h-4 mt-0.5 flex-shrink-0" />
            <p>
              Visit this link to join our commissions program via Rewardful (limit: $0/m)
            </p>
          </div>
        </Card>

        {/* Invite Others Section */}
        <Card className="bg-[#1A1F35] border-[#1E293B] p-6 mb-4">
          <h3 className="text-white mb-4">Invite others</h3>
          <div className="bg-[#0F172A] rounded-lg p-4 border border-[#1E293B] space-y-3">
            <div>
              <label className="text-[#94A3B8] text-sm mb-1 block">
                (After you have to join our affiliate program)
              </label>
              <input 
                type="text"
                placeholder="Send to email address via AMOS"
                className="w-full bg-transparent border border-[#1E293B] rounded-lg px-3 py-2 text-white placeholder:text-[#64748B]"
              />
            </div>
            <div>
              <label className="text-[#94A3B8] text-sm mb-1 block">
                Your website, blog, or social media channels (if applicable)
              </label>
              <textarea 
                placeholder="(Optional) marketing channels"
                rows={2}
                className="w-full bg-transparent border border-[#1E293B] rounded-lg px-3 py-2 text-white placeholder:text-[#64748B] resize-none"
              />
            </div>
          </div>
          <div className="flex items-start gap-2 text-sm text-[#94A3B8] mt-3">
            <Info className="w-4 h-4 mt-0.5 flex-shrink-0" />
            <p>This takes us understand how you'll promote AMOS</p>
          </div>
        </Card>

        {/* Reminder Banner */}
        <div className="bg-cyan-500/10 border border-cyan-500/20 rounded-lg p-4 flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-cyan-400 flex-shrink-0 mt-0.5" />
          <p className="text-cyan-400 text-sm">
            <span className="font-medium">Reminder Pass:</span> We typically review applications within 2 business days. You'll receive an email once your application is processed.
          </p>
        </div>
      </div>
    </div>
  );
}
