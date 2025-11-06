import { 
  Link,
  MessageSquare,
  FileText,
  Database,
  Users,
  Shield,
  Share2,
  BarChart3,
  UserCircle,
  Settings
} from 'lucide-react';
import { Button } from './ui/button';

export function ConnectionsSidebar() {
  return (
    <div className="w-64 bg-[#0F172A] border-r border-[#1E293B] p-6 flex flex-col">
      {/* Logo */}
      <div className="mb-8">
        <h1 className="text-white mb-1">Amos AI</h1>
        <p className="text-[#94A3B8] text-sm">Admin Portal</p>
      </div>

      {/* Navigation */}
      <nav className="flex-1 space-y-1">
        <Button 
          variant="ghost" 
          className="w-full justify-start text-white bg-[#7C3AED] hover:bg-[#7C3AED]/90"
        >
          <Link className="w-4 h-4 mr-3" />
          Connections
        </Button>
        
        <Button variant="ghost" className="w-full justify-start text-[#94A3B8] hover:text-white hover:bg-[#1E293B]">
          <Database className="w-4 h-4 mr-3" />
          Knowledge Base
        </Button>
        
        <Button variant="ghost" className="w-full justify-start text-[#94A3B8] hover:text-white hover:bg-[#1E293B]">
          <BarChart3 className="w-4 h-4 mr-3" />
          Analytics
        </Button>
        
        <Button variant="ghost" className="w-full justify-start text-[#94A3B8] hover:text-white hover:bg-[#1E293B]">
          <Users className="w-4 h-4 mr-3" />
          Affiliates
        </Button>
        
        <Button variant="ghost" className="w-full justify-start text-[#94A3B8] hover:text-white hover:bg-[#1E293B]">
          <UserCircle className="w-4 h-4 mr-3" />
          Team Members
        </Button>
        
        <Button variant="ghost" className="w-full justify-start text-[#94A3B8] hover:text-white hover:bg-[#1E293B]">
          <Shield className="w-4 h-4 mr-3" />
          Privacy Controls
        </Button>
        
        <Button variant="ghost" className="w-full justify-start text-[#94A3B8] hover:text-white hover:bg-[#1E293B]">
          <Share2 className="w-4 h-4 mr-3" />
          Social Media
        </Button>
      </nav>

      {/* Settings */}
      <Button variant="ghost" className="w-full justify-start text-[#94A3B8] hover:text-white hover:bg-[#1E293B]">
        <Settings className="w-4 h-4 mr-3" />
        Settings
      </Button>
    </div>
  );
}
