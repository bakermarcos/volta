# Instalar e jogar

O aparelho do jogo é um Mac ou uma Android TV. Os celulares entram pelo navegador, no mesmo Wi-Fi, sem instalar nada. A versão que vale para jogar é a release.

## Android TV

No computador, na pasta do projeto, com o modo depuração da TV ligado e o aparelho na mesma rede:

```sh
flutter build apk --release
adb connect IP_DA_TV:5555
adb -s IP_DA_TV:5555 install -r build/app/outputs/flutter-apk/app-release.apk
adb -s IP_DA_TV:5555 shell am start -n com.homegame.volta/.MainActivity
```

O pacote é `com.homegame.volta`. O APK sai em `build/app/outputs/flutter-apk/app-release.apk`.

Troque `IP_DA_TV` pelo endereço da TV. Se o `adb connect` falhar, confira o IP nas configurações da TV e se a depuração de rede está aceita.

Depois de instalar, abra o controle no celular de novo. A página vem da TV. Uma instalação nova só aparece no celular quando a página é recarregada.

## Mac

```sh
flutter pub get
flutter run -d macos --release
```

`flutter run` sem `--release` serve para desenvolver. A fluidez de jogo é a da release.

## Entrar na corrida

1. TV ou Mac e celulares no mesmo Wi-Fi. Rede de convidados com isolamento entre aparelhos não conecta.
2. Toque em **Começar**. Para uma volta sozinho contra o relógio, use **Tempo na pista**. Os dois abrem sala e QR.
3. Aponte a câmera do celular para o QR, ou digite o endereço mostrado na tela.
4. Escreva o nome e toque em **Estou pronto**. **Largar** libera quando todos estiverem prontos. Dá para correr sozinho.
5. No fim, **Jogar de novo** repete a mesma pista e os mesmos pilotos. **Voltar ao lobby** volta à escolha.

O controle usa dois polegares: direção à esquerda, pedal à direita. Deslizar o pedal para cima é o turbo. Deslizar para baixo freia e, se continuar, anda de ré.

## O que esta versão muda na corrida

- No asfalto, a velocidade normal chega a 405 e o turbo a 615. O modo turbo da sala multiplica os dois por 1,4. Na grama o limite continua 195.
- Curva mais fechada do que a pista cabe não joga mais a guia para dentro da reta. A faixa estreita na curva e a guia acompanha o asfalto.
- O minimapa aponta para o mesmo lado que a câmera. Ele só fica espelhado quando a sala está em **Espelhado**.
- O lobby do celular mostra o kart da TV, girando, com o fundo transparente.
- O histórico na TV rola com o controle remoto.

Números e comportamento acima são desta branch. O restante do jogo continua como o [README](../README.md) descreve.
