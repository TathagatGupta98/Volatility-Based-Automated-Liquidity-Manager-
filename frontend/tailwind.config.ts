import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        neon: {
          pink: '#ff4fd8',
          cyan: '#2be6ff',
          violet: '#7a5cff',
          green: '#3cf5a6'
        }
      },
      boxShadow: {
        glow: '0 0 0 1px rgba(255,255,255,0.08), 0 12px 48px rgba(90, 80, 255, 0.28)'
      }
    }
  },
  plugins: []
} satisfies Config;
