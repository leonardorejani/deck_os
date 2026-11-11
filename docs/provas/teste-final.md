# Teste final no iPhone (só o Leonardo faz)

Fecha a fase 8. Tudo aqui precisa do aparelho na mão, por isso nenhum item foi provado por mim. Marque cada um e anote o que falhar.
Pré-requisito: Deck.app instalado em Aplicativos pelo `dist/Deck-1.0.dmg` e aberto (ícone na barra de menus), iPhone de teste no mesmo Wi-Fi.

## PWA, pelo Wi-Fi

1. No Mac, abra o Deck > Ajustes > Conectar iPhone. Leia o QR com a câmera do iPhone.
2. Siga a tela do certificado: Baixar certificado, Ajustes > Perfil Transferido > Instalar, e confie nele em Ajustes > Geral > Sobre > Ajustes de Confiança de Certificados. Volte ao Safari e toque em Continuar. O painel tem que abrir com dados reais.
3. Compartilhar > Adicionar à Tela de Início. Abra pelo ícone novo: tem que ficar em tela cheia, sem barra do Safari.
4. Deite o iPhone e deixe uns minutos sem tocar. A tela tem que continuar acesa (Wake Lock) e o relógio deslocar 1 a 2 px de tempos em tempos.
5. Toque numa tecla que seja segura (por exemplo "Manter acordado"). Ela tem que executar no Mac e acender.
6. Segure uma tecla: modo organizar. Arraste uma, solte, e confira no Mac (Ajustes > Suas teclas) que a ordem mudou.
7. Desligue o Wi-Fi do Mac ou saia do Deck. Feche e abra o ícone no iPhone: a página tem que abrir na hora e mostrar o aviso "Mac desconectado". Ligue de novo e o painel tem que voltar sozinho.

## App nativo, cabo e Bluetooth

8. Abra o app Deck no iPhone (já instalado e confiado). Toque em "Procurar por perto" e no nome do Mac. Os dois mostram o mesmo código: confira e toque em Permitir no Mac.
9. Com o cabo desligado, confira que o painel carrega e que o aviso de 3 segundos diz "Pelo Bluetooth".
10. Toque numa tecla: o iPhone tem que vibrar de leve e a ação rodar no Mac.
11. Ligue o cabo e destrave o iPhone. O aviso de 3 segundos tem que dizer "Pelo cabo", sem o painel piscar nem perder o estado.
12. Puxe o cabo no meio, com o painel aberto. Em até uns segundos o aviso diz "Pelo Bluetooth" e o painel segue mostrando dado novo.
13. Em Ajustes > Conectar iPhone, confira "Último canal", a versão do app e a data da próxima renovação (5 dias depois da instalação).

## Anote

- Item que falhou, o que viu na tela e a hora (o log do Mac está em `~/Library/Logs/Deck/deck.log`).
- Daqui a 5 dias, conferir no mesmo log que a renovação automática rodou sozinha (linha `renovacao: ok`).
