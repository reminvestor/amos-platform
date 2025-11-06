import { 
  Users, 
  UserPlus,
  Mail,
  MoreVertical,
  Shield,
  Eye,
  Trash2
} from 'lucide-react';
import { Card } from './ui/card';
import { Button } from './ui/button';
import { Badge } from './ui/badge';

interface TeamMember {
  name: string;
  email: string;
  role: string;
  status: string;
  statusType: 'onboarded' | 'pending' | 'active';
  avatar: string;
}

export function TeamMembers() {
  const members: TeamMember[] = [
    {
      name: 'Jessica Chen',
      email: 'jchen@amos.com',
      role: 'Viewer',
      status: 'Never',
      statusType: 'pending',
      avatar: 'JC'
    },
    {
      name: 'Marcus Johnson',
      email: 'mjohnson@amos.com',
      role: 'Manager',
      status: 'Never',
      statusType: 'pending',
      avatar: 'MJ'
    },
    {
      name: 'Elena Rodriguez',
      email: 'elena@amos.com',
      role: 'Admin',
      status: '1 month ago',
      statusType: 'active',
      avatar: 'ER'
    }
  ];

  return (
    <div className="flex-1 bg-[#0A0E1A] overflow-auto">
      {/* Header */}
      <div className="border-b border-[#1E293B] px-8 py-6">
        <div className="flex items-center justify-between">
          <div>
            <div className="flex items-center gap-3 mb-2">
              <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[#7C3AED] to-[#A78BFA] flex items-center justify-center">
                <Users className="w-5 h-5 text-white" />
              </div>
              <h1 className="text-white">Team Members</h1>
            </div>
            <p className="text-[#94A3B8] ml-[52px]">Manage users in your entity</p>
          </div>
        </div>
      </div>

      {/* Main content */}
      <div className="p-8">
        {/* Action buttons */}
        <div className="flex items-center gap-3 mb-6">
          <Button 
            className="bg-emerald-500 hover:bg-emerald-600 text-white gap-2"
          >
            <UserPlus className="w-4 h-4" />
            Onboard
          </Button>
          <Button 
            className="bg-cyan-500 hover:bg-cyan-600 text-white gap-2"
          >
            <Mail className="w-4 h-4" />
            Invite The Team
          </Button>
        </div>

        {/* Team Members Table */}
        <Card className="bg-[#1A1F35] border-[#1E293B] overflow-hidden">
          <div className="px-6 py-4 border-b border-[#1E293B]">
            <h3 className="text-white">Team Members</h3>
          </div>
          
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-[#0F172A]">
                <tr>
                  <th className="text-left px-6 py-3 text-[#94A3B8]">Name</th>
                  <th className="text-left px-6 py-3 text-[#94A3B8]">Email</th>
                  <th className="text-left px-6 py-3 text-[#94A3B8]">Role</th>
                  <th className="text-left px-6 py-3 text-[#94A3B8]">Onboarded/Last Sign In</th>
                  <th className="text-left px-6 py-3 text-[#94A3B8]">Actions</th>
                </tr>
              </thead>
              <tbody>
                {members.map((member, index) => (
                  <tr 
                    key={index}
                    className="border-t border-[#1E293B] hover:bg-[#0F172A]/50 transition-colors"
                  >
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-full bg-gradient-to-br from-purple-500 to-pink-500 flex items-center justify-center">
                          <span className="text-white text-sm">{member.avatar}</span>
                        </div>
                        <span className="text-white">{member.name}</span>
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <span className="text-[#94A3B8]">{member.email}</span>
                    </td>
                    <td className="px-6 py-4">
                      <Badge 
                        className={`${
                          member.role === 'Admin' 
                            ? 'bg-purple-500/10 text-purple-400 border-purple-500/20' 
                            : member.role === 'Manager'
                            ? 'bg-cyan-500/10 text-cyan-400 border-cyan-500/20'
                            : 'bg-slate-500/10 text-slate-400 border-slate-500/20'
                        } border`}
                      >
                        {member.role}
                      </Badge>
                    </td>
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-2">
                        {member.statusType === 'pending' ? (
                          <div className="w-2 h-2 rounded-full bg-amber-500"></div>
                        ) : (
                          <div className="w-2 h-2 rounded-full bg-emerald-500"></div>
                        )}
                        <span className="text-white">{member.status}</span>
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <Button 
                        variant="ghost" 
                        size="sm"
                        className="text-cyan-400 hover:text-cyan-300 hover:bg-cyan-500/10"
                      >
                        View
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      </div>
    </div>
  );
}
