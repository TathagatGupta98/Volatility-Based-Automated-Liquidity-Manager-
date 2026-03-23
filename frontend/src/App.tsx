import { Navigate, Route, Routes } from 'react-router-dom';
import { AppShell } from './components/AppShell';
import { DashboardPage } from './pages/DashboardPage';
import { VaultActionsPage } from './pages/VaultActionsPage';
import { PositionsPage } from './pages/PositionsPage';
import { AutomationPage } from './pages/AutomationPage';
import { AdminPage } from './pages/AdminPage';

export default function App() {
  return (
    <AppShell>
      <Routes>
        <Route path="/" element={<Navigate to="/dashboard" replace />} />
        <Route path="/dashboard" element={<DashboardPage />} />
        <Route path="/vault-actions" element={<VaultActionsPage />} />
        <Route path="/positions" element={<PositionsPage />} />
        <Route path="/automation" element={<AutomationPage />} />
        <Route path="/admin" element={<AdminPage />} />
      </Routes>
    </AppShell>
  );
}
