# Volta na Google TV

## Agora: jogo no Mac, imagem na TV

- [ ] Ligar o Mac à TV por HDMI (adaptador USB-C/HDMI, se necessário).
- [ ] Selecionar a entrada HDMI na Google TV e colocar a imagem em modo Jogo, se disponível.
- [ ] Começar em 1920 × 1080 a 60 Hz. Validar seis jogadores antes de aumentar para 4K; 4K tem quatro vezes mais pixels.
- [ ] Usar a TV como tela do jogo: mover a janela do Volta para ela e ativar **Modo TV · tela cheia**. O modo usa a tela em que a janela estiver.
- [ ] Conferir que nomes, posição e voltas aparecem inteiros nas bordas. O HUD tem recuo de 5%; a corrida ocupa a tela, sem o cabeçalho do lobby.
- [ ] Conectar Mac e celulares à mesma rede local, sem isolamento de convidados. A TV precisa apenas receber a imagem HDMI; não hospeda a sala.
- [ ] Abrir uma nova sala e escanear seu QR. Recarregar a página do controle nos celulares para receber o layout novo.
- [ ] Testar com dois, quatro e seis celulares: esquerda/direita, direção suave, aceleração → turbo sem levantar o dedo, freio/ré, desconexão e retorno.
- [ ] Conferir a leitura a 2–3 metros e a fluidez com seis vistas. Os testes automatizados não substituem essa rodada no Wi-Fi real.
- [ ] Usar **Pausar** ou Esc para parar a corrida; confirmar que o histórico continua sendo salvo no Mac.

O controle remoto da Google TV seleciona a entrada e configura a TV. Ele não controla automaticamente os menus do app no Mac. Por enquanto o lobby usa mouse/teclado; os pilotos usam os celulares.

## App instalado na TV

O APK release existe e pode ser o aparelho do jogo. Ele serve o controle na rede local e navega com o controle remoto.

```sh
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am start -n com.homegame.volta/.MainActivity
```

Ainda falta medir fluidez com seis câmeras, validar a rodada presencial e, se for publicar, preparar a assinatura e os requisitos da Play Store.

## Inclinação do celular

O controle inclui detecção, permissão e calibração de inclinação quando o navegador permite sensores. No endereço atual `http://IP-DO-MAC:porta/...`, os navegadores modernos normalmente bloqueiam o sensor por não ser um contexto seguro. A página mantém o toque e explica a limitação. O HTTPS local agora pode ser preparado com `tool/setup_https.sh`. No iPhone, abra o link de preparação no controle e instale/confie no certificado público, depois use o link HTTPS. Veja o passo a passo no README. A instalação e a confiança no iPhone são manuais; o toque continua disponível sem esse preparo.

## Referências verificadas

- [Google: layouts de TV, leitura à distância e margem segura](https://developer.android.com/training/tv/playback/compose/layouts)
- [Google: criar um app para Android TV](https://developer.android.com/training/tv/get-started/create)
- [Google: controles de TV e navegação por direcional](https://developer.android.com/training/tv/get-started/controllers)
- [Apple: alcance dos polegares, controles grandes e combinação de ações](https://developer.apple.com/design/human-interface-guidelines/game-controls)
- [Flutter Scene: plataformas e ativação da GPU](https://pub.dev/packages/flutter_scene)
- [MDN: permissão de orientação e exigência de contexto seguro](https://developer.mozilla.org/en-US/docs/Web/API/DeviceOrientationEvent/requestPermission_static)
