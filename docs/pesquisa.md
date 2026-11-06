# Pesquisa

Duas ideias, nenhuma implementada: ler um DualShock 4 na página do celular, e colocar poderes na pista. Nada disto entra no jogo agora. Os fatos de navegador foram conferidos nas fontes do final, em 6 de novembro de 2026. Onde o comportamento não foi medido neste projeto, o texto diz isso.

## Controle Bluetooth no celular

O celular é um navegador. A página em `assets/controller.html` não é um aplicativo nativo, e o Web Bluetooth não fala HID de gamepad.

A [Web Bluetooth API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Bluetooth_API) alcança periféricos Bluetooth Low Energy pelo GATT, e só em contexto seguro. O DualShock 4 entrega eixos e botões por Bluetooth clássico HID. Esse canal não é um serviço GATT que a página possa assinar. O serviço HID sobre GATT (`00001812-0000-1000-8000-00805f9b34fb`) está na [lista de bloqueio](https://raw.githubusercontent.com/WebBluetoothCG/registries/master/gatt_blocklist.txt), para uma página não ler teclado. O [WebHID](https://developer.mozilla.org/en-US/docs/Web/API/WebHID_API), que no Chrome de desktop lê relatórios HID, não existe no Chrome para Android — o Android não oferece à Web a API de HID que o Chromium precisaria — nem no Safari do iPhone.

O caminho realista é o sistema. O piloto emparelha o DualShock 4 nos ajustes de Bluetooth do celular. A página lê o controle que o sistema já entregou ao navegador, com `navigator.getGamepads()`, e traduz eixos e gatilhos nas mensagens que o WebSocket já carrega: `accelerate`, `reverse` e `steer`. No lobby, o Cross manda o `ready` que o botão **Estou pronto** já manda.

### Contexto seguro

A Gamepad API não exige HTTPS. A página `http://IP-da-TV:porta` deve enxergar o controle.

A especificação retirou `SecureContext` em fevereiro de 2024 ([w3c/gamepad#194](https://github.com/w3c/gamepad/pull/194)). O algoritmo atual de [`getGamepads()`](https://w3c.github.io/gamepad/#dom-navigator-getgamepads) devolve lista vazia antes de um gesto no controle e lança `SecurityError` apenas quando a Permissions Policy `gamepad` bloqueia a origem. A política padrão é `*` ([MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/gamepad)). A ficha da MDN para [`Navigator.getGamepads()`](https://developer.mozilla.org/en-US/docs/Web/API/Navigator/getGamepads) não lista contexto seguro; a exceção documentada é essa política.

O Chrome nunca chegou a impor a restrição. Ficou numa flag, `#restrict-gamepad-access`, e num aviso; os dados de compatibilidade da MDN marcam a exigência como ausente no Chrome, e o Chrome para Android espelha isso. O WebKit removeu o aviso de contexto inseguro em fevereiro de 2024 ([WebKit#24550](https://github.com/WebKit/WebKit/pull/24550)). O Firefox exigiu HTTPS da versão 91 até a 124 e deixou de exigir na 125. O Volta não depende do Firefox.

`tool/setup_https.sh` continua sendo o caminho da inclinação. O sensor de movimento pede contexto seguro, e o HTTP pelo IP local bloqueia esse sensor, como o README já descreve. O certificado local não é pré-requisito do controle. Uma página HTTP enxerga o pad.

Isto não foi medido com um DualShock nesta rede. Se um teste futuro vir o controle só no endereço HTTPS, o resultado contradiz as fontes acima e precisa ser anotado. Até lá, o certificado não entra no caminho só por causa do pad.

### Android Chrome e Safari no iPhone

No Android, o emparelhamento é confiável e a leitura no Chrome é o alvo razoável. A [Sony](https://www.playstation.com/en-us/support/hardware/ps4-pair-dualshock-4-wireless-with-pc-or-mac/) documenta o DualShock 4 por Bluetooth a partir do Android 10. O Chrome para Android implementa a Gamepad API ([caniuse](https://caniuse.com/gamepad)). O Chromium tem mapeamento de DualShock 4 por USB e por Bluetooth, e um commit corrige, no Android, Share, Options e os cliques dos analógicos, além do adaptador USB.

O mapeamento `standard` no Android Chrome não está garantido por um teste deste projeto. Um [relato](https://github.com/sigmaxipi/chromium-for-stadia/issues/5) no Chrome para Android viu o mesmo controle com `id` "Wireless Controller", sem a marca "STANDARD GAMEPAD", gatilhos fora dos índices 6 e 7, e o touchpad entregue como mouse. Não retestei um celular atual. O teste de botões na página continua obrigatório antes de fixar qualquer índice.

No iPhone, o emparelhamento de sistema é confiável e o Safari é a parte frágil. Desde o iOS 13 o Game Controller framework aceita o DualShock 4 ([WWDC19](https://developer.apple.com/videos/play/wwdc2019/616/)); a Sony lista o mesmo piso. O Safari tem Gamepad API desde o iOS 10.3. No [bug 205448](https://bugs.webkit.org/show_bug.cgi?id=205448), o WebKit registrou que o DualShock 4 funciona no Safari a partir do iOS 13, depois de um toque no controle. Fora da tela cheia, o relato de 2026 diz que os gatilhos chegam.

Três limites do Safari importam:

- Em tela cheia, o Safari 26.5 deixa de atualizar os botões 4 a 7, isto é L1, R1, L2 e R2. O [bug 311151](https://bugs.webkit.org/show_bug.cgi?id=311151) seguia sem correção registrada quando a página foi lida; o último comentário, de 20 de maio de 2026, confirma a falha no iOS e no iPadOS 26.5. L2 e R2 são o freio e o acelerador deste esboço. A página do Volta não entra em tela cheia. Pedir tela cheia quebraria os pedais.
- O iOS também usa o controle como navegação de foco. O [Safari 26.1](https://webkit.org/blog/17541/webkit-features-for-safari-26-1/) precisou corrigir o botão B, que fazia a página perder o foco do gamepad pela navegação automática do sistema. O Cross pode acionar o botão HTML focado e, ao mesmo tempo, aparecer na Gamepad API. Isso não foi medido nesta página.
- Não há medição de 2026 desta página HTTP com um DualShock no iPhone. O identificador que o Safari costuma expor para um controle estendido inclui "Extended Gamepad" ([w3c/gamepad#199](https://github.com/w3c/gamepad/issues/199)). Isso indica reconhecimento pelo sistema. Não substitui o teste dos índices.

Aba em segundo plano para o controle. A especificação só expõe o pad depois de um gesto com a página visível e em primeiro plano. O Chromium não despacha atualização de gamepad com o documento oculto ([w3c/gamepad#215](https://github.com/w3c/gamepad/issues/215)). `controller.html` já zera a direção quando a página fica oculta ou perde o foco. Um controle numa aba de fundo para de dirigir.

O gesto é da especificação, não de um navegador isolado. `getGamepads()` devolve lista vazia até o piloto apertar um botão ou deslocar um analógico com a página visível. Se o controle já estava pareado quando a página abriu, `gamepadconnected` espera esse gesto ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/Gamepad_API/Using_the_Gamepad_API)). Consultar a lista antes disso não mostra o pad. O Firefox descreve a mesma trava com a página visível; o Chrome também esconde o controle até o gesto.

### Esboço de mapeamento

Vale apenas quando `mapping` é `"standard"`. A [tabela do W3C](https://w3c.github.io/gamepad/#remapping) coloca o DualShock assim:

- Eixo 0, analógico esquerdo na horizontal. Negativo é esquerda, positivo é direita. Alimenta o `steer` que a página já envia, com zona neutra da mesma família da do toque.
- Botão 7, gatilho inferior direito (R2). O `value` vai de 0 a 1. Acima de um limiar, `accelerate` fica verdadeiro. No layout padrão o gatilho é botão analógico, não um eixo.
- Botão 6, gatilho inferior esquerdo (L2). O `value` liga `reverse`. O host já freia antes de engatar a ré ao receber esse campo.
- Botão 0, botão inferior do grupo direito. No DualShock é o Cross. No lobby, envia o `ready` existente. Durante a corrida, não dirige.

O turbo do piloto continua no gesto do pedal na tela. Este esboço não acrescenta botão de boost.

Se `mapping` não for `"standard"`, esses índices estão errados. O teste, uma vez, mostra na própria página qual índice se move quando o piloto mexe o analógico esquerdo e aperta R2, L2 e Cross. Só então a página passa a preencher os campos. A leitura é uma consulta por quadro ao objeto devolvido naquela chamada. O objeto guardado do evento `gamepadconnected` não acompanha o quadro seguinte.

### Recomendação

O controle por toque precisa estar sólido antes disto. O primeiro passo, quando chegar a hora, é consultar `getGamepads()` dentro de `assets/controller.html`, só no Chrome para Android, na página HTTP que o celular já abre. O teste de botões vem antes de ligar os campos ao WebSocket. O Safari fica fora desse passo. Sem aplicativo nativo e sem Web Bluetooth.

## Poderes e turbos na pista

A corrida autoritativa é uma, em `lib/game/race.dart`. O celular manda entrada. A tela dividida já desenha cada carro a partir do estado do host. Efeito novo se decide no host, no mesmo passo que já integra velocidade, boost, contato e voltas.

O boost do piloto já sobe o teto. Com aceleração, sem ré, no asfalto, acima de 40 e com carga, o teto passa de 270 para 410 e a aceleração de 165 para 370. Na grama o teto é 195. A opção Turbo da sala multiplica todo o ritmo por 1,4, à parte dessa carga. A carga esvazia em 1,6 s de boost contínuo. Uma placa, ou o efeito de velocidade de uma caixa, reutiliza esse impulso: o host aplica o teto de 410 por um tempo curto e fixo, sem gastar a carga do piloto e sem mensagem nova do celular. A opção Turbo da sala continua multiplicando o teto como já faz. Com o piloto já em boost, o teto não sobe outra vez.

### Fase 1. Placas de boost

Zonas fixas no circuito, por intervalo de ângulo da pista ou por um trecho entre checkpoints. A pista já é um ângulo, e os 16 checkpoints nascem em ângulos iguais. A zona é a mesma em toda volta, no traçado em que for colocada. Ao cruzar, o host aplica o impulso acima.

É determinístico. A marca fica visível na malha da pista. Não há sorteio e não há alvo em outro piloto. A posição ao longo da volta já está em `trackAngle` e `progress`. O celular não guarda estado de placa.

### Fase 2. Caixas

Uma coleta, um efeito, três possibilidades. O sorteio ocorre no host quando o carro cruza a caixa.

1. Impulso de velocidade. O mesmo teto da placa, pela mesma janela curta.
2. Mancha de óleo. O host cria uma zona curta na pista. Quem a atravessa perde aderência por pouco tempo: a direção que o host já integra responde menos, e o carro abre a trajetória. A zona tem prazo.
3. Freada curta em quem vai à frente. O host olha a ordem por `progress` e abaixa o teto de velocidade do próximo carro. Sem carro à frente, o efeito não acontece. Não há projétil nem mira.

Casco, raio e estrela cabem mal em seis vistas na GPU da TV. Um casco é um objeto a mais em cada câmera, com colisão e reação. Um raio pinta todas as vistas ao mesmo tempo. Uma estrela pede invulnerabilidade e uma leitura visual própria. Os tempos do README são do Mac em profile, não da Google TV, e a rodada com seis celulares no Wi-Fi ainda não aconteceu. O celular também não tem lugar para item. A telemetria leva o estado do próprio piloto, no máximo cinco vezes por segundo. Segurar e mirar um item pede tela no celular e mensagem nova. Os três efeitos acima se resolvem no host quando a caixa é pega ou quando o carro atravessa a mancha. O celular continua mandando acelerar, ré, boost e direção.

### Justiça

O sorteio fica em `race.dart`. A página não escolhe o efeito. A mesma ativação serve um carro: o host a consome na primeira passagem. O carro seguinte não recebe outro efeito daquela caixa.

Desconectar não deixa armadilha permanente. A mancha guarda um prazo no passo da corrida. Fechar a página já faz o carro frear. A mancha não espera o soquete continuar aberto. No fim do prazo, a zona acaba.

### Fora deste passo

Sem arte nova. Uma placa futura pode ser uma faixa na malha que já existe. Sem inventário no celular. Sem campo novo no WebSocket enquanto uma telemetria tardia, por exemplo um texto `effect`, não for necessária.

### Recomendação

As placas de boost vêm antes das caixas, e só depois que a taxa de quadros na TV estiver estável. A placa reutiliza o teto que o host já aplica no boost do piloto, fica fixa na pista e dispensa sorteio, tela no celular e mensagem nova. A caixa mexe em outro piloto e precisa expirar. Ela espera as placas estarem no jogo e as seis vistas segurarem o quadro na televisão.

## Fontes

Conferidas em 6 de novembro de 2026.

Gamepad API e contexto seguro:

- [Navigator.getGamepads() — MDN](https://developer.mozilla.org/en-US/docs/Web/API/Navigator/getGamepads)
- [Gamepad API — MDN](https://developer.mozilla.org/en-US/docs/Web/API/Gamepad_API)
- [Using the Gamepad API — MDN](https://developer.mozilla.org/en-US/docs/Web/API/Gamepad_API/Using_the_Gamepad_API)
- [Permissions-Policy: gamepad — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Permissions-Policy/gamepad)
- [Especificação Gamepad (W3C)](https://w3c.github.io/gamepad/)
- [Remoção de SecureContext na especificação](https://github.com/w3c/gamepad/pull/194)
- [Compatibilidade da MDN: Gamepad deixa de exigir contexto seguro](https://github.com/mdn/browser-compat-data/commit/8a1c73bd3ade55a42a65b285b66f4d6399c78b84)
- [Firefox 125 remove a restrição; Chrome e Safari não a tinham imposto](https://groups.google.com/a/mozilla.org/g/dev-platform/c/RFiv1oCsAvY)
- [Firefox 91, quando a restrição existiu só no Gecko](https://developer.mozilla.org/en-US/docs/Mozilla/Firefox/Releases/91)

Web Bluetooth e WebHID:

- [Web Bluetooth API — MDN](https://developer.mozilla.org/en-US/docs/Web/API/Web_Bluetooth_API)
- [Lista de bloqueio GATT, serviço HID `00001812-…`](https://raw.githubusercontent.com/WebBluetoothCG/registries/master/gatt_blocklist.txt)
- [WebHID API — MDN](https://developer.mozilla.org/en-US/docs/Web/API/WebHID_API)
- [WebHID ausente no Android e no Safari — caniuse](https://caniuse.com/webhid)
- [WICG WebHID: Chrome no Android não implementa](https://github.com/WICG/webhid/)

Android, Chrome e iOS / WebKit:

- [Sony: DualShock 4 em Android 10 e iOS 13](https://www.playstation.com/en-us/support/hardware/ps4-pair-dualshock-4-wireless-with-pc-or-mac/)
- [Gamepad API no Chrome para Android e no Safari do iOS — caniuse](https://caniuse.com/gamepad)
- [Mapeamento por barramento no Chromium, cabeçalho público](https://chromium.googlesource.com/chromium/src/+/refs/tags/130.0.6682.3/device/gamepad/gamepad_standard_mappings.h)
- [Commit do Chromium: mapeamento do DualShock 4 no Android](https://github.com/webb-3w/chromium-src/commit/f1dc344fa6a3730b9872a50bf24e8f4a849cbd9a)
- [Relato de ordem errada no Chrome para Android, não retestado aqui](https://github.com/sigmaxipi/chromium-for-stadia/issues/5)
- [Apple, WWDC19: DualShock 4 no Game Controller framework](https://developer.apple.com/videos/play/wwdc2019/616/)
- [WebKit remove o aviso de contexto inseguro](https://github.com/WebKit/WebKit/pull/24550)
- [WebKit 205448: DualShock 4 no Safari a partir do iOS 13](https://bugs.webkit.org/show_bug.cgi?id=205448)
- [WebKit 311151: em tela cheia, botões 4–7 somem no Safari 26.5](https://bugs.webkit.org/show_bug.cgi?id=311151)
- [Safari 26.1: correção do botão B e do foco do gamepad no iOS 26](https://webkit.org/blog/17541/webkit-features-for-safari-26-1/)
- [Identificador "Extended Gamepad" no Safari](https://github.com/w3c/gamepad/issues/199)
- [Chromium só entrega gamepad com a página visível](https://github.com/w3c/gamepad/issues/215)
