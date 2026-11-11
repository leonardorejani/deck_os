// Junta, para cada tela, a foto do app (mac-swift-<tela>.png), a do protótipo (mac-proto-<tela>.png)
// e a diferença entre as duas (mac-comparacao-<tela>.png). Uso:
//   node comparar.mjs <pasta-das-fotos> [tela ...]
// Imprime a porcentagem de pixels que diferem mais de 24/255 (só para dar ideia: o que vale é olhar).
// Playwright: `npm i playwright` ou aponte a variável PLAYWRIGHT para o index.mjs de uma instalação existente.
const { chromium } = await import(process.env.PLAYWRIGHT || 'playwright');
import { readdirSync, readFileSync } from 'node:fs';

const [pasta, ...pedidas] = process.argv.slice(2);
if (!pasta) { console.error('Uso: node comparar.mjs <pasta-das-fotos> [tela ...]'); process.exit(2); }
const telas = readdirSync(pasta).filter(f => f.startsWith('mac-swift-')).map(f => f.slice(10, -4)).filter(t => !t.startsWith('extra-')).filter(t => !pedidas.length || pedidas.includes(t));
const dado = f => 'data:image/png;base64,' + readFileSync(`${pasta}/${f}`).toString('base64');

const navegador = await chromium.launch({ channel: 'chrome' });
for (const t of telas) {
  const pagina = await navegador.newPage({ viewport: { width: 2400, height: 1800 }, deviceScaleFactor: 1 });
  await pagina.setContent(`<body style="margin:0;background:#1C1C1C;color:#ddd;font:14px sans-serif">
    <div style="display:flex;gap:24px;padding:16px;align-items:flex-start" id="linha">
      <figure style="margin:0"><figcaption>protótipo</figcaption><img id="a" src="${dado(`mac-proto-${t}.png`)}"></figure>
      <figure style="margin:0"><figcaption>app (SwiftUI)</figcaption><img id="b" src="${dado(`mac-swift-${t}.png`)}"></figure>
      <figure style="margin:0"><figcaption>diferença</figcaption><canvas id="c"></canvas></figure>
    </div>`);
  const dif = await pagina.evaluate(async () => {
    const a = document.getElementById('a'), b = document.getElementById('b'), c = document.getElementById('c');
    await Promise.all([a, b].map(i => i.decode()));
    const w = Math.max(a.naturalWidth, b.naturalWidth), h = Math.max(a.naturalHeight, b.naturalHeight);
    const ler = (img) => { const k = document.createElement('canvas'); k.width = w; k.height = h; const x = k.getContext('2d'); x.fillStyle = '#1C1C1C'; x.fillRect(0, 0, w, h); x.drawImage(img, 0, 0); return x.getImageData(0, 0, w, h).data };
    const A = ler(a), B = ler(b);
    c.width = w; c.height = h; const x = c.getContext('2d'); const saida = x.createImageData(w, h);
    let ruins = 0;
    for (let i = 0; i < A.length; i += 4) {
      const d = Math.max(Math.abs(A[i] - B[i]), Math.abs(A[i + 1] - B[i + 1]), Math.abs(A[i + 2] - B[i + 2]));
      if (d > 24) ruins++;
      const v = Math.min(255, d * 4);
      saida.data[i] = v; saida.data[i + 1] = v; saida.data[i + 2] = v; saida.data[i + 3] = 255;
    }
    x.putImageData(saida, 0, 0);
    return { w, h, pct: (100 * ruins / (w * h)).toFixed(2), tamA: [a.naturalWidth, a.naturalHeight], tamB: [b.naturalWidth, b.naturalHeight] };
  });
  await pagina.locator('#linha').screenshot({ path: `${pasta}/mac-comparacao-${t}.png` });
  console.log(`${t}: protótipo ${dif.tamA.join('x')}, app ${dif.tamB.join('x')}, ${dif.pct}% dos pixels diferem`);
  await pagina.close();
}
await navegador.close();
