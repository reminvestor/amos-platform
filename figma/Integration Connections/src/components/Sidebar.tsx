import { Home, Globe, Link2, Eye, Users, BarChart3, Settings, LogOut } from 'lucide-react';
import { Button } from './ui/button';

interface NavItem {
  icon: React.ReactNode;
  label: string;
  active?: boolean;
}

export function Sidebar() {
  const navItems: NavItem[] = [
    { icon: <Home className="w-5 h-5" />, label: 'Dashboard', active: false },
    { icon: <Globe className="w-5 h-5" />, label: 'Services Health', active: false },
    { icon: <Link2 className="w-5 h-5" />, label: 'Connections', active: true },
    { icon: <Eye className="w-5 h-5" />, label: 'Observability', active: false },
    { icon: <Users className="w-5 h-5" />, label: 'Users', active: false },
    { icon: <BarChart3 className="w-5 h-5" />, label: 'AI Pipeline', active: false },
  ];

  return (
    <div className="w-64 bg-[#0F172A] h-screen flex flex-col border-r border-[#1E293B]">
      {/* Logo */}
      <div className="p-6 flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#7C3AED] to-[#A78BFA] flex items-center justify-center">
          <span className="text-white">A</span>
        </div>
        <span className="text-white">Admin Portal</span>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-3 space-y-1">
        {navItems.map((item, index) => (
          <button
            key={index}
            className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg transition-colors ${
              item.active
                ? 'bg-[#1E293B] text-white'
                : 'text-[#94A3B8] hover:bg-[#1E293B]/50 hover:text-white'
            }`}
          >
            {item.icon}
            <span>{item.label}</span>
          </button>
        ))}
      </nav>

      {/* Bottom section */}
      <div className="p-3 space-y-1 border-t border-[#1E293B]">
        <button className="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-[#94A3B8] hover:bg-[#1E293B]/50 hover:text-white transition-colors">
          <Settings className="w-5 h-5" />
          <span>Settings</span>
        </button>
        <button className="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-[#94A3B8] hover:bg-[#1E293B]/50 hover:text-white transition-colors">
          <LogOut className="w-5 h-5" />
          <span>Logout</span>
        </button>
      </div>
    </div>
  );
}
