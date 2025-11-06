import { ConnectionsSidebar } from './components/ConnectionsSidebar';
import { Connections } from './components/Connections';

export default function App() {
  return (
    <div className="flex h-screen bg-[#0A0E1A] dark">
      <ConnectionsSidebar />
      <Connections />
    </div>
  );
}
