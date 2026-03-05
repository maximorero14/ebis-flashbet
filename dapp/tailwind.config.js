/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      fontFamily: {
        orbitron: ['Orbitron', 'sans-serif'],
        mono:     ['JetBrains Mono', 'monospace'],
      },
      colors: {
        neon: {
          cyan:    '#00f5ff',
          purple:  '#a855f7',
          magenta: '#f0abfc',
        },
        up:      '#4ade80',
        down:    '#f43f5e',
        surface: '#0f172a',
        border:  '#1e293b',
      },
      backgroundImage: {
        'cyber-grid': `
          linear-gradient(rgba(0,245,255,0.03) 1px, transparent 1px),
          linear-gradient(90deg, rgba(0,245,255,0.03) 1px, transparent 1px)
        `,
      },
      backgroundSize: {
        'cyber-grid': '40px 40px',
      },
      animation: {
        'pulse-up':   'pulse-up 2s ease-in-out infinite',
        'pulse-down': 'pulse-down 2s ease-in-out infinite',
      },
      keyframes: {
        'pulse-up': {
          '0%, 100%': { boxShadow: '0 0 15px rgba(74,222,128,0.4)' },
          '50%':      { boxShadow: '0 0 30px rgba(74,222,128,0.8)' },
        },
        'pulse-down': {
          '0%, 100%': { boxShadow: '0 0 15px rgba(244,63,94,0.4)' },
          '50%':      { boxShadow: '0 0 30px rgba(244,63,94,0.8)' },
        },
      },
    },
  },
  plugins: [],
}
