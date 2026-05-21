import { Routes, Route, Navigate } from "react-router-dom";
import Layout from "./components/Layout";
import Dashboard from "./pages/Dashboard";
import SystemOverview from "./pages/SystemOverview";
import Network from "./pages/Network";
import CameraConnectivity from "./pages/CameraConnectivity";
import Services from "./pages/Services";
import DiskHealth from "./pages/DiskHealth";
import EventViewer from "./pages/EventViewer";
import Reports from "./pages/Reports";
import Settings from "./pages/Settings";
import About from "./pages/About";
import ScoreConnect from "./pages/ScoreConnect";
import FaultIsolator from "./pages/FaultIsolator";

export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="dashboard" element={<Dashboard />} />
        <Route path="system" element={<SystemOverview />} />
        <Route path="network" element={<Network />} />
        <Route path="cameras" element={<CameraConnectivity />} />
        <Route path="services" element={<Services />} />
        <Route path="disk" element={<DiskHealth />} />
        <Route path="events" element={<EventViewer />} />
        <Route path="reports" element={<Reports />} />
        <Route path="scoreconnect" element={<ScoreConnect />} />
        <Route path="fault-isolator" element={<FaultIsolator />} />
        <Route path="settings" element={<Settings />} />
        <Route path="about" element={<About />} />
      </Route>
    </Routes>
  );
}
