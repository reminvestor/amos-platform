import { 
  LayoutDashboard, 
  Megaphone, 
  Image as ImageIcon, 
  Share2, 
  BookOpen, 
  DollarSign, 
  Settings, 
  Users, 
  BarChart3, 
  ShieldCheck, 
  Lock,
  ChevronDown,
  Sparkles
} from 'lucide-react';

interface NavItem {
  icon: React.ReactNode;
  label: string;
  active?: boolean;
  expandable?: boolean;
}

interface NavSection {
  title?: string;
  items: NavItem[];
}

export function AnalyticsSidebar() {
  const navSections: NavSection[] = [
    {
      items: [
        { icon: <LayoutDashboard className="w-5 h-5" />, label: 'Dashboard', active: false },
        { icon: <Megaphone className="w-5 h-5" />, label: 'Marketing', active: false, expandable: true },
        { icon: <ImageIcon className="w-5 h-5" />, label: 'Images', active: false },
        { icon: <Share2 className="w-5 h-5" />, label: 'Social Media', active: false },
        { icon: <BookOpen className="w-5 h-5" />, label: 'Knowledge Base', active: false },
      ],
    },
    {
      title: 'EARN MONEY',
      items: [
        { icon: <DollarSign className="w-5 h-5" />, label: 'Join Affiliates', active: false },
        { icon: <Settings className="w-5 h-5" />, label: 'Settings', active: false, expandable: true },
      ],
    },
    {
      title: 'MANAGEMENT',
      items: [
        { icon: <Users className="w-5 h-5" />, label: 'Team Members', active: false },
        { icon: <BarChart3 className="w-5 h-5" />, label: 'Analytics', active: true },
        { icon: <ShieldCheck className="w-5 h-5" />, label: 'AI Policies', active: false },
        { icon: <Lock className="w-5 h-5" />, label: 'Privacy Controls', active: false },
      ],
    },
    {
      title: 'PLATFORM ADMIN',
      items: [
        { icon: <Sparkles className="w-5 h-5" />, label: 'Admin Portal', active: false },
      ],
    },
  ];

  return (
    <div className="w-64 bg-[#0F172A] h-screen flex flex-col border-r border-[#1E293B] overflow-y-auto">
      {/* Logo */}
      <div className="p-6 flex items-center gap-3 border-b border-[#1E293B]">
        <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[#7C3AED] to-[#A78BFA] flex items-center justify-center">
          <span className="text-white">S</span>
        </div>
        <span className="text-white">Scout</span>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-3 py-4">
        {navSections.map((section, sectionIndex) => (
          <div key={sectionIndex} className="mb-6">
            {section.title && (
              <div className="px-3 mb-2">
                <span className="text-[#64748B] text-xs tracking-wider">{section.title}</span>
              </div>
            )}
            <div className="space-y-1">
              {section.items.map((item, itemIndex) => (
                <button
                  key={itemIndex}
                  className={`w-full flex items-center justify-between gap-3 px-3 py-2.5 rounded-lg transition-colors ${
                    item.active
                      ? 'bg-[#1E293B] text-white'
                      : 'text-[#94A3B8] hover:bg-[#1E293B]/50 hover:text-white'
                  }`}
                >
                  <div className="flex items-center gap-3">
                    {item.icon}
                    <span>{item.label}</span>
                  </div>
                  {item.expandable && (
                    <ChevronDown className="w-4 h-4" />
                  )}
                </button>
              ))}
            </div>
          </div>
        ))}
      </nav>
    </div>
  );
}
