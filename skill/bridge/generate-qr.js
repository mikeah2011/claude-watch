import QRCode from 'qrcode';
import fs from 'fs';

const deepLink = process.argv[2] || 'agentwatch://pair?url=http://127.0.0.1:7860&code=000000';
const outputPath = '/tmp/agent-watch-qr.png';

QRCode.toFile(outputPath, deepLink, {
  type: 'png',
  width: 400,
  margin: 2,
  color: {
    dark: '#000000',
    light: '#FFFFFF'
  }
}, (err) => {
  if (err) {
    console.error('Error generating QR code:', err);
    process.exit(1);
  }
  console.log(`QR code saved to: ${outputPath}`);
  console.log(`Deep Link: ${deepLink}`);
});
