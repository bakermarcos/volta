# volta

Corrida arcade **3D para 1 a 6 pessoas**, com tela dividida no Mac ou na Android TV e controles no navegador dos celulares. O aparelho do jogo calcula uma única corrida e mostra uma câmera atrás do kart de cada piloto. Flutter Scene 0.24.3 renderiza a cena na GPU.

## Jogar

Use release para jogar com desempenho real. Para desenvolvimento com hot reload, use `flutter run -d macos`; o modo debug não serve como referência de fluidez.

```sh
flutter pub get
flutter run -d macos --release
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

1. Conecte Mac e celulares ao mesmo Wi-Fi.
2. No Mac ou na TV, toque em **Começar**. Autorize o acesso à rede local caso o macOS solicite. A instalação na TV está em [docs/instalacao.md](docs/instalacao.md).
3. Clique no nome da pista para escolher um dos 16 traçados da referência ou a Ilha Brisa.
4. Leia o QR com a câmera normal do celular e abra o endereço no Safari/Chrome. Também é possível digitar o endereço completo exibido no Mac.
5. Digite o nome no celular e toque em **Estou pronto**. Quando todos estiverem prontos, clique em **Largar**. É possível jogar sozinho.
6. A largada espera a pista carregar, aproxima a câmera com **Está pronto?** e só então conta 3, 2, 1. O controle já fica aberto na contagem: segurar o acelerador prepara o carro parado e ele sai quando a contagem termina. Se o kart seguir contra o sentido da pista, a tela e o celular avisam **Contra mão**.

A corrida usa a tela inteira disponível: duas vistas para dois jogadores; três ou quatro vistas em duas linhas; cinco ou seis vistas em duas linhas com até três colunas. Cada vista tem nome, cor, posição, volta, velocidade e carga do boost. A animação das rodas acompanha o deslocamento, com giro limitado para evitar estroboscopia, e as rodas dianteiras acompanham a direção. O lobby mostra uma visão geral da pista.

### Controle

- **Dois polegares:** direção à esquerda, um pedal combinado à direita. Funciona na vertical e na horizontal.
- **Direção analógica:** toque em qualquer ponto da área e arraste a partir dali. Zona neutra, curva gradual e sensibilidade padrão de 75%, ajustável nos ajustes do controle. Soltar centraliza.
- **Acelerar:** segure o pedal à direita.
- **Turbo:** com o mesmo dedo no pedal, deslize para cima. Continua acelerando; volte ao centro para aceleração normal. Ao esgotar, volte ao centro antes de tentar novamente.
- **Freio / ré:** deslize o mesmo dedo para baixo. Freia primeiro; mantendo pressionado, passa a andar de ré. Soltar o pedal freia.
- **Inclinação:** opção com calibração para navegadores que oferecem sensores em contexto seguro. O HTTP pelo IP local normalmente bloqueia sensores: nessa situação a página explica e mantém o touch. O HTTPS local está disponível; veja a configuração para iPhone abaixo.
- Na grama, o limite é 195 contra 405 no asfalto. O turbo no asfalto chega a 615. A queda de velocidade é gradual. O turbo continua exclusivo do asfalto.

**Treinar com teclado:** Lima usa W/S, A/D e Shift; Azul usa ↑/↓, ←/→ e Espaço. Esc ou o botão Pausar pede uma pausa; repita em até quatro segundos para confirmar. Ao continuar, a simulação retoma sem acumular o tempo da pausa.

**Modo TV:** mova a janela do Mac para a TV e ative o modo para entrar em tela cheia e ampliar textos. O jogo usa toda a tela durante a corrida; os HUDs ficam recuados das bordas. Consulte [a lista de preparação da Google TV](TV_CHECKLIST.md). A versão Android TV também pode ser instalada por ADB; veja o checklist.

## Conexão local

O Mac serve a página do controle por HTTP e recebe os botões por WebSocket. Não há Firebase, conta, instalação no celular, exigência de internet nem serviço externo. Comandos e conexões ficam na memória; resultados são salvos em um arquivo JSON no Mac. Apenas os controles passam pela rede: toda a simulação e todas as câmeras ficam no Mac.

O QR contém um endereço local com código aleatório. Cada piloto recebe um token próprio, e os comandos ficam vinculados à sua conexão. Posição, energia do boost e resultados são calculados pelo Mac. A telemetria enviada ao celular contém apenas o estado do próprio piloto, até cinco vezes por segundo. A simulação avança no mesmo tick da cena 3D; entradas atualizam o estado sem reconstruir os menus a cada pacote.

Os controles usam limite de frequência e heartbeat a cada 300 ms. Comandos sem atualização por 1,8 s são neutralizados. Desconectar faz o carro frear; o mesmo navegador pode voltar ao mesmo kart por até 15 s antes de abandonar. **Sair** libera a vaga; **Remover desconectados**, no lobby, libera vagas de páginas fechadas.

Se houver mais de uma interface de rede, escolha no lobby o IP do Wi-Fi. Redes de convidados com isolamento entre dispositivos impedem a conexão. Não abra portas no roteador: o controle por toque usa HTTP/WebSocket na rede local; a inclinação pode usar HTTPS/WSS com certificado local. Se o firewall perguntar, permita conexões do app volta na rede local. Apenas 4G/5G ou outro Wi-Fi não alcançam o Mac. Reabrir a sala gera outro QR/endereço.

## Histórico local

**Histórico** no Mac e **Histórico de corridas** no site dos controles mostram pista, data, classificação, tempos e desistências. O placar soma corridas e vitórias pelo nome (sem distinguir maiúsculas/minúsculas); use sempre o mesmo nome. Uma corrida em que todos saíram não atribui vitória. Corridas interrompidas antes do fim não entram no histórico.

O arquivo `races.json` fica em `Library/Application Support/volta/` dentro do diretório do app no Mac (com sandbox: `~/Library/Containers/com.homegame.volta/Data/Library/Application Support/volta/`). Sobrevive a fechar o app e criar novas salas. A gravação usa arquivo temporário e substituição após conclusão. O site consulta o histórico no Mac enquanto a sala estiver aberta, inclusive antes de entrar; nada é enviado à nuvem.

As pistas usam asfalto com 240 unidades de largura, suficiente para quatro karts de aproximadamente 31 unidades com folga. O traçado é ampliado proporcionalmente até suas bordas, incluindo margem de separação, não se cruzarem. Asfalto, grama e pneus compartilham a mesma altura; a pintura usa camadas de profundidade.


## Voltas e fim da corrida

Cada volta exige cruzar **16 checkpoints em ordem e no sentido correto**, contando também a faixa de grama de escape. A área de escape tem 90 unidades além do asfalto; uma barreira invisível, sinalizada pelos postes, impede sair desse corredor e atravessar o miolo. O limite acompanha o trecho atual da pista para evitar saltar para uma reta próxima. Cortar caminho não completa os checkpoints pulados: retorne ao trecho faltante. A tela não mostra o número do checkpoint. A chegada conta apenas depois de completar essa sequência, pelo número de voltas escolhido.

A tela mostra tempo da corrida e da volta. Quando **todos menos um** terminam, o último tem **15 segundos** para chegar. Se chegar antes, encerra imediatamente; caso contrário, aparece como não concluído. Solo encerra na chegada. O resultado tem celebração, classificação, tempo total, melhor volta e tempos individuais. **Jogar de novo** repete a corrida. **Voltar ao lobby** preserva a configuração e o último placar. Todos precisam confirmar Pronto para a próxima partida.

## Inclinação no iPhone por HTTPS local

Uma vez no Mac, execute `tool/setup_https.sh` e reabra a sala. O script usa OpenSSL 3.5 LTS atualizado para criar uma autoridade local e um certificado para o IP atual. Chaves privadas ficam apenas na pasta HTTPS do app, com acesso restrito. Não há túnel nem nuvem.

No Safari do iPhone, abra o controle HTTP e toque em **Preparar inclinação no iPhone antes de entrar**. A página permite baixar o certificado público e explica como instalar o perfil e ativar confiança total em Ajustes → Geral → Sobre → Ajustes de Confiança de Certificado. Depois abra o link HTTPS indicado, entre na sala e toque em Usar inclinação. Essa confiança precisa ser ativada manualmente no iPhone. Se mudar o IP do Mac, rode o script novamente e reabra a sala; a autoridade local permanece a mesma. Para remover a confiança, apague o perfil no iPhone.

## Desempenho verificado

Cena e modelos de karts são reutilizados entre lobby e corrida; marcações, postes e cenário estático usam instâncias. Controles não reconstruem a interface a cada pacote e o HUD atualiza a 30 Hz. No Mac, em profile com seis vistas, a medição desta versão registrou UI p95 **10,79 ms** e raster p95 **10,55 ms**. A verificação de profundidade não apontou conflitos. Esses números não são uma medição na Google TV.

## Código e dependências

- `lib/game/race.dart`: movimento, ré, boost, contato entre karts, voltas e classificação.
- `lib/game/circuit.dart` e `track_layouts.dart`: curvas, distância à pista e contornos da referência.
- `lib/room/room_service.dart`: HTTP/WebSocket, presença e comandos.
- `lib/room/session.dart`: ciclo de vida da sala com ChangeNotifier.
- `lib/room/race_history.dart`: resultados em JSON, gravação local e placar de vitórias.
- `lib/ui/race_scene.dart`: geometria 3D procedural, câmeras por jogador e HUDs.
- `lib/ui/host.dart`: lobby, escolha da pista, largada e resultado.
- `assets/controller.html`: controle responsivo sem biblioteca JavaScript.

Dependências conferidas no pub.dev e na API instalada: Flutter Scene **0.24.3**, fixado por ainda estar antes da versão 1.0; vector_math **2.4.4**; qr **4.0.1**. `hooks` 2.2.0 prepara os assets do Scene. A marca e o ícone estão em `assets/volta_logo.svg`, `assets/volta_icon.svg` e `assets/volta_banner.svg`. Nenhuma dependência de execução em Python. A extração pontual da imagem não faz parte do app.

O Flame foi avaliado e não adicionado: a renderização 3D fica no Scene, sem sobrepor motores. Fluorite não foi adotado porque o site ainda apresenta acesso público como futuro. Os modelos e cenários são procedurais e originais; não usam personagens ou assets da Nintendo.

## Planos futuros

- Alargar o asfalto para comportar cerca de oito karts lado a lado. Os circuitos já estão mais compactos e “chubby”; esse aumento adicional deve manter os trechos separados. Isso define a largura desejada; o limite atual continua sendo seis jogadores.
- Adicionar um botão de drift em uma etapa posterior, preservando a ergonomia do controle com dois polegares.

Estas ideias estão registradas para depois; não fazem parte da implementação atual.

## Validar

```sh
flutter analyze
flutter test
node --test test/controller_test.mjs
flutter build macos --debug
```

Os testes cobrem controles, ré, boost, recarga, curvas/voltas, os 16 traçados, grids de largada, divisão da tela de 1 a 6 vistas, seleção de pista, seis conexões locais, isolamento dos comandos, saída, reconexão, resultado, nova corrida, persistência após reinício e consulta do histórico pelo HTTP. A renderização precisa também de validação no Mac: testes de widget não exercitam a GPU.

Ambiente: Flutter 3.47.2 / Dart 3.13.2 / Xcode 26.3 / macOS 26.3.1. Flutter GPU está habilitado em `macos/Runner/Info.plist`; o Scene compila seus shaders pelos build hooks. A primeira compilação é mais lenta. Ainda falta a rodada presencial com seis celulares no Wi-Fi real; os testes de rede usam sockets locais.

Se a assinatura falhar com `resource fork, Finder information` em uma pasta sincronizada como Documentos, use um build fora dessa sincronização e remova somente os atributos extras do artefato gerado antes de recompilar. Não é necessário desativar assinatura ou proteções do macOS.

## Projeto Firebase anterior

O projeto `volta-home-game-2026` foi criado antes da decisão de usar somente a rede local. Não integra esta versão nem recebe dados do jogo. O banco foi fechado para leitura/escrita e o login anônimo foi desativado. Excluir esse projeto é uma ação independente do aplicativo.

## Pesquisa

Duas ideias foram estudadas e não estão implementadas: controle Bluetooth no celular com DualShock 4, e poderes na pista no estilo Mario Kart. O levantamento está em [docs/pesquisa.md](docs/pesquisa.md).

Quem pode fazer merge na `master` e quem pode atualizar as outras branches está em [docs/repositorio.md](docs/repositorio.md).
