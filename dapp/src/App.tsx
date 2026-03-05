/**
 * App — componente raíz de FlashBet DApp.
 *
 * Configura el routing con react-router-dom:
 *   /         → HomePage (Vault + Prediction Markets)
 *   /history  → HistoryPage (historial de rondas del usuario)
 *
 * Incluye el layout compartido: Navbar + Footer.
 * Las notificaciones toast se montan aquí para disponibilidad global.
 */
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { Toaster } from 'react-hot-toast'
import { Navbar } from './components/layout/Navbar'
import { Footer } from './components/layout/Footer'
import { VaultPage } from './pages/VaultPage'
import { MarketsPage } from './pages/MarketsPage'
import { HistoryPage } from './pages/HistoryPage'
import { AdminPage } from './pages/AdminPage'
import { AccountWatcher } from './components/AccountWatcher'

export default function App() {
  return (
    <BrowserRouter>
      {/* Vídeo de fondo — bucle silencioso en todas las pantallas */}
      <video
        autoPlay
        muted
        loop
        playsInline
        style={{
          position: 'fixed',
          inset: 0,
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          zIndex: -2,
          pointerEvents: 'none',
        }}
      >
        <source src="/video1.mp4" type="video/mp4" />
      </video>

      {/* Overlay oscuro — atenúa el vídeo para mantener el estilo cyberpunk sin perder legibilidad */}
      <div
        style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(3,7,18,0.92)',
          zIndex: -1,
          pointerEvents: 'none',
        }}
      />

      {/* Toast notifications — tema cyberpunk dark */}
      <Toaster
        position="top-right"
        toastOptions={{
          style: {
            background: '#0f172a',
            color: '#f1f5f9',
            border: '1px solid #1e293b',
            fontFamily: "'JetBrains Mono', monospace",
            fontSize: '13px',
            borderRadius: '10px',
          },
          success: { iconTheme: { primary: '#00f5ff', secondary: '#030712' } },
          error: { iconTheme: { primary: '#f43f5e', secondary: '#030712' } },
        }}
      />

      {/* Sincroniza el estado al cambiar de wallet */}
      <AccountWatcher />

      <div className="flex flex-col min-h-screen" style={{ position: 'relative', zIndex: 1 }}>
        <Navbar />
        <div className="flex-1">
          <Routes>
            <Route path="/" element={<Navigate to="/vault" replace />} />
            <Route path="/vault" element={<VaultPage />} />
            <Route path="/markets" element={<MarketsPage />} />
            <Route path="/history" element={<HistoryPage />} />
            <Route path="/admin" element={<AdminPage />} />
            <Route path="*" element={<Navigate to="/vault" replace />} />
          </Routes>
        </div>
        <Footer />
      </div>
    </BrowserRouter>
  )
}
