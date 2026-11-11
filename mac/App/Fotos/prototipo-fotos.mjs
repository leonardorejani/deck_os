// Fotografa as telas do protótipo do Mac (prototipo/mac.html) em escala 2, com o mesmo nome e os
// mesmos dados de exemplo das telas de Telas.swift. Uso:
//   node prototipo-fotos.mjs <porta> <pasta-de-saida> [tela ...]
// A porta é de um `python3 -m http.server <porta>` rodando dentro de prototipo/.
// Playwright: `npm i playwright` ou aponte a variável PLAYWRIGHT para o index.mjs de uma instalação existente.
const { chromium } = await import(process.env.PLAYWRIGHT || 'playwright');

const [porta, saida, ...pedidas] = process.argv.slice(2);
if (!porta || !saida) { console.error('Uso: node prototipo-fotos.mjs <porta> <pasta-de-saida> [tela ...]'); process.exit(2); }

const TECLAS_BASE = `M.perfil='leo'; M.iphone='on'; M.perms={acess:true,cal:true,spotify:false,disco:false}; M.busca=''`;
// mais quatro teclas no perfil Trabalho: passam de 5 e a segunda página aparece
const MAIS_TECLAS = `[['Safari','Safari'],['Notas','Notes'],['Terminal','Terminal'],['Finder','Finder']].forEach(([n,a],i)=>teclas.push({id:'t-x'+(i+1),nome:n,tipo:'app',valor:a,icone:a}))`;

// abre a janela e deixa a seção do tamanho do conteúdo (sem rolar)
const INTEIRA = `abrirJanela('teclas'); $('#janela').style.height='auto'; $('#janela').style.overflow='visible'; corpo.style.overflow='visible'; $('#mesa').style.height='2600px'; $('#mesa').style.overflow='visible'; $('#palco').style.height='auto'; $('#palco').style.overflow='visible'`;

// Cada tela: como deixar o protótipo no estado e o que fotografar.
const TELAS = {
  'menu': { estado: `M.perfil='leo'; M.iphone='on'; M.configurado=true; M.perms={acess:true,cal:true,spotify:false,disco:false}; M.pop=true; pintar()`, alvo: '#popover' },
  'menu-sem-iphone': { estado: `M.perfil='leo'; M.iphone='off'; M.configurado=true; M.perms={acess:true,cal:true,spotify:false,disco:false}; M.pop=true; pintar()`, alvo: '#popover' },
  'menu-novo': { estado: `M.perfil='novo'; M.iphone='off'; M.configurado=false; M.perms={acess:true,cal:true,spotify:true,disco:true}; M.pop=true; pintar()`, alvo: '#popover' },
  'ajustes-casca': { estado: `M.perfil='leo'; M.iphone='on'; M.perms={acess:true,cal:true,spotify:false,disco:false}; abrirJanela('teclas'); $('#j-corpo').innerHTML=''`, alvo: '#janela' },
  'ajustes-casca-sem-iphone': { estado: `M.perfil='leo'; M.iphone='off'; M.perms={acess:true,cal:true,spotify:true,disco:true}; abrirJanela('sobre'); $('#j-corpo').innerHTML=''`, alvo: '#janela' },
  // Suas teclas (perfil Trabalho de exemplo, dados.js). Fotografam a seção inteira, sem rolagem (a janela cresce), para comparar o que fica abaixo da dobra.
  'teclas-app': { estado: `${TECLAS_BASE}; M.sel='whatsapp'; ${INTEIRA}`, alvo: '#j-corpo' },
  'teclas-app-busca': { estado: `${TECLAS_BASE}; M.sel='whatsapp'; M.busca='sa'; ${INTEIRA}`, alvo: '#j-corpo' },
  'teclas-teclado': { estado: `${TECLAS_BASE}; M.sel='acordado'; ${INTEIRA}`, alvo: '#j-corpo' },
  'teclas-comando': { estado: `${TECLAS_BASE}; M.sel='apagar'; ${INTEIRA}`, alvo: '#j-corpo' },
  'teclas-atalho': { estado: `${TECLAS_BASE}; teclas.push({id:'t-atalho',nome:'Modo Ensaio',tipo:'atalho',valor:'Modo Ensaio',icone:'svg:raio'}); M.sel='t-atalho'; ${INTEIRA}`, alvo: '#j-corpo' },
  'teclas-gravando': { estado: `${TECLAS_BASE}; M.sel='acordado'; M.ouvindo=true; ${INTEIRA}`, alvo: '#j-corpo' },
  'teclas-paginas': { estado: `${TECLAS_BASE}; ${MAIS_TECLAS}; M.sel='t-x4'; M.pag=1; ${INTEIRA}`, alvo: '#j-corpo' },
  'teclas-vazio': { estado: `${TECLAS_BASE}; teclas.splice(0); M.sel=null; ${INTEIRA}`, alvo: '#j-corpo' },
  'aviso-desfazer': { estado: `${TECLAS_BASE}; abrirJanela('teclas'); avisar('"Apagar tela" excluída', () => {})`, alvo: '#aviso' },
  'aviso-simples': { estado: `${TECLAS_BASE}; abrirJanela('teclas'); avisar('Safari escolhido')`, alvo: '#aviso' },
  'teclas-ensaio': { estado: `${TECLAS_BASE}; editarPerfil('ensaio'); ${INTEIRA}`, alvo: '#j-corpo' },
  // Uso das IAs e Adicionar conta (relógio parado em 10/11/2026 12h: "renova em 3 dias" tem de sair igual)
  'ajustes-uso': { relogio: true, estado: `M.perfil='leo'; M.iphone='on'; M.perms={acess:true,cal:true,spotify:false,disco:false}; abrirJanela('uso')`, alvo: '#janela' },
  'ajustes-uso-limite': { relogio: true, estado: `M.perfil='leo'; M.iphone='on'; M.perms={acess:true,cal:true,spotify:false,disco:false}; USO[1].sem=93; USO[2].mostrar=false; abrirJanela('uso')`, alvo: '#janela' },
  'ajustes-uso-hover': { relogio: true, estado: `M.perfil='leo'; M.iphone='on'; M.perms={acess:true,cal:true,spotify:false,disco:false}; abrirJanela('uso')`, passar: '.dash .conta:nth-child(2)', alvo: '#janela' },
  'adicionar-conta-claude': { relogio: true, estado: `M.perfil='leo'; M.iphone='on'; M.perms={acess:true,cal:true,spotify:false,disco:false}; USO.splice(1,1); abrirJanela('uso'); abrirConta()`, alvo: '#janela' },
  'adicionar-conta-codex': { relogio: true, estado: `M.perfil='leo'; M.iphone='on'; M.perms={acess:true,cal:true,spotify:false,disco:false}; abrirJanela('uso'); abrirConta(); M.conta.serv='Codex'; pintarConta()`, alvo: '#janela' },
  'adicionar-conta-erro': { relogio: true, estado: `M.perfil='leo'; M.iphone='on'; M.perms={acess:true,cal:true,spotify:false,disco:false}; USO.splice(1,1); abrirJanela('uso'); abrirConta(); M.conta.token='sk-ant-oat01-curto'; M.conta.nome='Trabalho'; adicionarToken()`, alvo: '#janela' },
  'uso-aviso-desfazer': { relogio: true, estado: `M.perfil='leo'; M.iphone='on'; M.perms={acess:true,cal:true,spotify:false,disco:false}; USO.splice(1,1); abrirJanela('uso'); avisar('Conta equipe removida', () => {})`, alvo: '#janela' },
  'ajustes-iphone': { estado: `M.perfil='leo'; M.iphone='on'; M.perms={acess:true,cal:true,spotify:false,disco:false}; abrirJanela('iphone'); const c=document.querySelector('.codigo'); if(c) c.textContent='482 913';`, alvo: '#janela' },
  'ajustes-iphone-sem-iphone': { estado: `M.perfil='leo'; M.iphone='off'; M.perms={acess:true,cal:true,spotify:true,disco:true}; abrirJanela('iphone'); const c=document.querySelector('.codigo'); if(c) c.textContent='482 913';`, alvo: '#janela' },
  // App nativo (fase 5): o estado vem de nativo-dados.js (et: vazio, confirmar, pronto. ren: ok, pendente, falhou)
  'ajustes-iphone-nativo-vazio': { relogio: true, estado: `M.perfil='leo'; M.iphone='off'; M.perms={acess:true,cal:true,spotify:true,disco:true}; abrirJanela('iphone'); const c=document.querySelector('.codigo'); if(c) c.textContent='482 913';`, alvo: '#janela' },
  'ajustes-iphone-nativo-confirmar': { relogio: true, estado: `M.perfil='leo'; M.iphone='off'; M.perms={acess:true,cal:true,spotify:true,disco:true}; nativoPublicar({et:'confirmar'}); abrirJanela('iphone'); document.querySelectorAll('.codigo').forEach((c,i)=>{ c.textContent = i === 0 ? '483 291' : '482 913' })`, alvo: '#janela' },
  'ajustes-iphone-nativo-pronto': { relogio: true, estado: `M.perfil='leo'; M.iphone='off'; M.perms={acess:true,cal:true,spotify:true,disco:true}; nativoPublicar({et:'pronto',ren:'ok',canal:'bluetooth'}); abrirJanela('iphone'); const c=document.querySelector('.codigo'); if(c) c.textContent='482 913';`, alvo: '#janela' },
  'ajustes-iphone-nativo-pendente': { relogio: true, estado: `M.perfil='leo'; M.iphone='off'; M.perms={acess:true,cal:true,spotify:true,disco:true}; nativoPublicar({et:'pronto',ren:'pendente',canal:'bluetooth'}); abrirJanela('iphone'); const c=document.querySelector('.codigo'); if(c) c.textContent='482 913';`, alvo: '#janela' },
  'ajustes-iphone-nativo-aperta': { relogio: true, estado: `M.perfil='leo'; M.iphone='off'; M.perms={acess:true,cal:true,spotify:true,disco:true}; nativoPublicar({et:'pronto',ren:'falhou',canal:'bluetooth'}); abrirJanela('iphone'); const c=document.querySelector('.codigo'); if(c) c.textContent='482 913';`, alvo: '#janela' },
  'menu-nativo-confirmar': { relogio: true, estado: `M.perfil='leo'; M.iphone='off'; M.configurado=true; M.perms={acess:true,cal:true,spotify:true,disco:true}; nativoPublicar({et:'confirmar'}); M.pop=true; pintar()`, alvo: '#popover' },
  'menu-nativo-aperta': { relogio: true, estado: `M.perfil='leo'; M.iphone='off'; M.configurado=true; M.perms={acess:true,cal:true,spotify:true,disco:true}; nativoPublicar({et:'pronto',ren:'falhou',canal:'bluetooth'}); M.pop=true; pintar()`, alvo: '#popover' },
  'aviso': { estado: `abrirJanela('iphone'); avisar('Endereço copiado')`, alvo: '#aviso' },
  'ajustes-acessos': { estado: `M.perfil='leo'; M.iphone='on'; M.perms={acess:true,cal:true,spotify:false,disco:false,nav:true,bt:true,rede:true}; abrirJanela('permissoes')`, alvo: '#janela' },
  'ajustes-acessos-vazio': { estado: `M.perfil='leo'; M.iphone='on'; M.perms={acess:true,cal:true,spotify:true,disco:true,nav:true,bt:true,rede:true}; abrirJanela('permissoes')`, alvo: '#janela' },
  'ajustes-este-mac': { estado: `M.perfil='leo'; M.iphone='on'; M.perms={acess:true,cal:true,spotify:false,disco:false}; abrirJanela('geral')`, alvo: '#janela' },
  'ajustes-sobre': { estado: `M.perfil='leo'; M.iphone='on'; M.perms={acess:true,cal:true,spotify:false,disco:false}; abrirJanela('sobre')`, alvo: '#janela' },
  'ajustes-sobre-sem-iphone': { estado: `M.perfil='leo'; M.iphone='off'; M.perms={acess:true,cal:true,spotify:true,disco:true}; abrirJanela('sobre')`, alvo: '#janela' },
};

// Configuração inicial: perfil "Usuário novo" (trocarPerfil abre a configuração), no passo pedido.
const ini = (passo, depois = '') => ({ estado: `trocarPerfil('novo'); M.ini.passo = ${passo}; ${depois}; pintarIni(0)`, alvo: '#ini' });
Object.assign(TELAS, {
  'inicial-boas': ini(0),
  'inicial-iphone': ini(1),
  'inicial-iphone-conectado': ini(1, "M.ini.conectado = true; M.iphone = 'on'"),
  'inicial-layout': ini(2),
  'inicial-layout-b': ini(2, "M.ini.comp = 'b'"),
  'inicial-contas': ini(3),
  'inicial-contas-uma': ini(3, "M.ini.contas.delete('codex')"),
  'inicial-teclas': ini(4),
  'inicial-acessos': ini(5),
  'inicial-acessos-depois': ini(5, "M.perms.cal = true; M.perms.spotify = false"),
  'inicial-pronto': ini(6),
  'inicial-pronto-conectado': ini(6, "M.ini.conectado = true; M.iphone = 'on'"),
});

const navegador = await chromium.launch({ channel: 'chrome' });
const pagina = await navegador.newPage({ viewport: { width: 1600, height: 3000 }, deviceScaleFactor: 2 });
let falhas = 0;
for (const [nome, t] of Object.entries(TELAS)) {
  if (pedidas.length && !pedidas.includes(nome)) continue;
  if (t.relogio) await pagina.clock.install({ time: new Date('2026-11-10T12:00:00') });
  await pagina.goto(`http://localhost:${porta}/mac.html`);
  await pagina.evaluate(() => {
    // `ui-monospace` é SF Mono no Safari, mas o Chrome cai numa fonte com serifa: Menlo é a mais parecida que ele tem.
    // sem animação de abertura, sem o pano de fundo da mesa, e escala 1: a foto é só do elemento
    const css = document.createElement('style');
    css.textContent = '*{animation:none!important;transition:none!important} html,body,.mesa{background:transparent!important} .endereco,.endereco *{font-family:Menlo,monospace!important}';
    document.head.append(css);
    document.querySelector('#mesa').style.setProperty('--escala', 1);
    document.querySelector('#mesa').style.transform = 'none';
  });
  await pagina.evaluate(t.estado);
  if (t.passar) await pagina.hover(t.passar);
  await pagina.waitForTimeout(150);
  const arquivo = `${saida}/mac-proto-${nome}.png`;
  await pagina.locator(t.alvo).screenshot({ path: arquivo, omitBackground: true });
  console.log('ok', arquivo);
}
await navegador.close();
process.exit(falhas);
