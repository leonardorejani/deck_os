// "fotos do whatsapp demoram pra carregar, umas nem carregam" (13/11/2026). Foto de perfil na lista: poucos pedidos ao mesmo
// tempo, falha de rede tenta de novo (antes ficava sem foto até recarregar) e a miniatura fica no aparelho.
// Dados inventados do Mac de mentira (servidor-falso.mjs).
const pronta = (h, p) => h.espera(p, () => !document.querySelector('#conteudo.carregando') && !!document.querySelector('.tecla[data-id="apagar"]'));
const comFoto = p => p.evaluate(() => document.querySelectorAll('#wa-lista .conversa .avatar img').length);

export default async function (h) {
  /* ---------- poucos pedidos ao mesmo tempo ---------- */
  await h.cenario({ whatsappOrigem: 'qr', whatsappRico: true, whatsappFotos: 12, fotoAtraso: 150 });
  let p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  const t0 = Date.now();
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa .avatar img').length >= 13, undefined, 8000), `as 13 fotos aparecem (${await comFoto(p)})`);
  const c = await h.contadores();
  console.log(`      13 fotos de 150 ms cada em ${Date.now() - t0} ms, no máximo ${c.fotoPico} ao mesmo tempo`);
  h.ok(c.fotoPico <= 3, `no máximo 3 pedidos de foto ao mesmo tempo (pico ${c.fotoPico})`);
  h.ok(c.fotos.length === 13 && new Set(c.fotos).size === 13, `cada foto é pedida uma vez só (${c.fotos.length})`);

  /* ---------- a lista não espera as fotos ---------- */
  await p.close(); await h.reset();
  await h.cenario({ whatsappOrigem: 'qr', whatsappRico: true, whatsappFotos: 12, fotoAtraso: 1500 });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  h.ok(await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length >= 12, undefined, 1200), 'a lista aparece sem esperar as fotos');
  h.ok(await comFoto(p) === 0, 'e quem ainda não tem foto mostra a inicial');

  /* ---------- falha de rede tenta de novo ---------- */
  await p.close(); await h.reset();
  await h.cenario({ whatsappOrigem: 'qr', whatsappRico: true, fotoFalhaPrimeira: true });
  p = await h.pagina(); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  await h.espera(p, () => document.querySelectorAll('#wa-lista .conversa').length >= 4);
  await h.dormir(600);
  h.ok(await comFoto(p) === 0, 'o primeiro pedido falhou: fica a inicial por enquanto');
  h.ok(await h.espera(p, () => !!document.querySelector('#wa-lista .conversa .avatar img'), undefined, 6000), 'a foto aparece sozinha depois da falha (antes ficava sem foto até recarregar)');
  const c2 = await h.contadores();
  h.ok(c2.fotos.length === 2, `foram 2 pedidos: o que falhou e o de novo (${c2.fotos.length})`);

  /* ---------- a miniatura fica no aparelho ---------- */
  await p.close(); await h.reset();
  const ctx = await h.novoContexto();
  await h.cenario({ whatsappOrigem: 'qr', whatsappRico: true });
  p = await h.pagina({ ctx }); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  await h.espera(p, () => !!document.querySelector('#wa-lista .conversa .avatar img'));
  await p.close();
  await h.reset();
  await h.cenario({ whatsappOrigem: 'qr', whatsappRico: true });
  p = await h.pagina({ ctx }); await pronta(h, p);
  await p.click('.tecla[data-id="whatsapp"]');
  h.ok(await h.espera(p, () => !!document.querySelector('#wa-lista .conversa .avatar img')), 'abrindo de novo a foto já está lá');
  h.ok((await h.contadores()).fotos.length === 0, 'sem pedir a foto ao Mac outra vez');
  await ctx.close();
}
