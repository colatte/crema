# Crema

> Utilitário minimalista de macOS que mostra o now playing perto da notch (ou num card flutuante em telas sem notch) e substitui os HUDs nativos de volume, brilho da tela e brilho do teclado por versões próprias, com estilo selecionável (global hoje; armazenado e resolvido por display — a seleção por display é roadmap).

Use este documento sempre que gerar ou alterar código neste repositório — ele diz **como escrevemos código aqui**: arquitetura, convenções, naming, concorrência e como as camadas conversam. Quando uma decisão de convenção for tomada durante a implementação, registre-a aqui — este documento evolui junto com o código.

## Stack

| Camada                      | Tecnologia                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Linguagem                   | Swift, em modo de linguagem Swift 6 (`SWIFT_VERSION = 6.0` — strict concurrency verificada pelo compilador)                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| UI e animações              | SwiftUI                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Janelas e ciclo de vida     | AppKit — NSPanel borderless; app accessory (LSUIElement)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Now playing                 | mediaremote-adapter (bridge em Perl) em todas as versões suportadas; fallback via JXA; checagem de disponibilidade — nunca MediaRemote direto                                                                                                                                                                                                                                                                                                                                                                                                      |
| Displays externos           | **Os dois sentidos existem, só para o display interno.** Entrada: `BetterDisplayOSDSource` consome a notificação de OSD (`pro.betterdisplay.BetterDisplay.osd`) e desenha o HUD de brilho. Volta: `BetterDisplayCommandChannel` + `BetterDisplayScreenBrightnessController` mandam o arrasto do slider de volta pelo canal request/response (`…​.request` → `…​.response`, casado por uuid, sob deadline), para a escrita cair na mesma escala da barra. Display **externo** é alcançável e fica de fora por **apresentação**, não por atuação: o mesmo HUD é desenhado em todos os painéis e nenhum diz de qual display é — ver ROADMAP.md. Lunar (socket `lunar listen`) segue roadmap |
| Distribuição                | Download direto, fora da Mac App Store; **assinado com certificado self-signed** (identidade de código estável entre versões, então o grant de Acessibilidade persiste; não satisfaz o Gatekeeper — "abrir mesmo assim" no primeiro launch; **nunca com hardened runtime** — a library validation exige Team ID real e um cert self-signed não tem, o app crasharia no load do Sparkle; o `release.sh` guarda isso com checagem de consistência + launch smoke). **Sparkle integrado** (SPM 2.9.4, exact; compilado só em Release via `#if !DEBUG`) — ciclo de update **operante desde a v1.2.0** (appcast publicado no Pages). `scripts/release.sh` também implementa o caminho Developer ID + notarização, aguardando conta Apple Developer — ver ROADMAP.md |
| Alvo                        | macOS 14+ (Sonoma), Apple Silicon e Intel, com e sem notch                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |

> **Construído vs. roadmap:** da integração com displays externos existe **só a entrada, e só para o display interno** — o `BetterDisplayOSDSource` desenha o HUD de brilho a partir da notificação do BetterDisplay (docs/DECISIONS.md: betterdisplay-osd-source); **atuar** sobre display externo (sentido inverso) e o Lunar seguem roadmap (ver [ROADMAP.md](ROADMAP.md)), então o que o app *controla* continua sendo o display interno + volume do sistema. O **Sparkle está integrado** e o ciclo de update **opera desde a v1.2.0** (appcast publicado no Pages); o caminho Developer ID + notarização existe pronto no `release.sh`, aguardando conta Apple Developer. O shipping segue self-signed ("abrir mesmo assim" no primeiro launch). Adiante, o que diz respeito a **atuar** sobre display externo descreve como a arquitetura o acomoda quando existir, não feature atual.

## Estrutura de pastas

Estrutura de pastas do app, espelhada pelos testes em `CremaTests/`.

```
crema/                       # raiz do repositório
├── README.md                # visão geral pública, instalação, uso, licença
├── ROADMAP.md               # direções futuras (público)
├── CONTRIBUTING.md          # como contribuir
├── LICENSE                  # GPL-3.0
├── CLAUDE.md                # este arquivo — convenções de código
├── docs/                    # documentação pública; também a raiz do GitHub Pages (publicado da main)
│   ├── README.md                    # mapa da documentação; o Pages o renderiza como homepage do site — links de repositório absolutos, nunca relativos
│   ├── DECISIONS.md                 # memória de design: decisões nomeadas e jurisprudência de classes de bug (âncoras citadas em comentários de código)
│   ├── design-reference.md          # pesquisa: estilos e polish visual
│   ├── osd-suppression-reference.md # pesquisa: supressão do OSD nativo
│   ├── appcast.xml                  # feed do Sparkle (vivo desde a v1.2.0; regenerado pelo release.sh, nunca editado à mão)
│   ├── assets/                      # imagens do README: screenshots da vitrine + icon.png (export web do appiconset)
│   └── internal/            # gitignored (local-only): SPEC.md, PLAN.md, RELEASE-GUIDE.md, auditorias e investigações
├── design/
│   ├── badge/               # makedownloadbadge.swift — gera o botão "Download for macOS" do README (docs/assets/download-macos.png); chão calibrado contra os dois temas do GitHub
│   └── icon/                # arte-fonte do ícone: master 4096 (sem máscara), makeicon.swift (aplica o squircle do template macOS e gera o appiconset), makemenubaricon.swift (deriva o TEMPLATE da barra de menus — pill + linha de crema), icns completo
├── scripts/
│   └── release.sh           # build + carimbo do build number + assinatura (ad-hoc / self-signed / Developer ID + notarização, incl. o código aninhado do Sparkle) + DMG + regeneração do docs/appcast.xml
├── ThirdParty/
│   └── mediaremote-adapter/ # bridge de now playing vendorizada (BSD-3-Clause)
├── Crema.xcodeproj          # projeto Xcode
├── Crema/                   # código do app
│   ├── Assets.xcassets/     # AppIcon (gerado por design/icon/makeicon.swift) + MenuBarIcon (template da barra, gerado por design/icon/makemenubaricon.swift, incl. o Contents.json com o template-rendering-intent obrigatório) — regenerar lá, nunca editar à mão
│   ├── App/                 # entry point (LSUIElement), menu da barra, Settings, onboarding de Acessibilidade, Preferences, login item, updater Sparkle (Release-only), política lock-aware da supressão, demo infra (#if DEBUG)
│   ├── Domain/              # tipos próprios do app (NowPlaying, SystemHUD, MediaKey, PresentationState, DisplayUUID) — nada da Apple vaza pra cima
│   ├── Sources/             # camada Fontes: integração com o sistema (a parte frágil); PROTOCOLOS e fontes compostas na raiz, implementações por tecnologia nos subdiretórios
│   │   ├── NowPlaying/      # mediaremote-adapter + fallback JXA + cadeia de disponibilidade (nunca MediaRemote direto)
│   │   ├── Volume/          # volume do sistema (Core Audio)
│   │   ├── Brightness/      # brilho da tela (DisplayServices) e do teclado (CoreBrightness) — ver "Nunca fazer"
│   │   ├── MediaKeys/       # event tap das teclas de mídia (exige permissão de Acessibilidade)
│   │   ├── OSDSuppression/  # supressão do OSD nativo por interceptação de teclas — opt-in, reversível, aplicar+verificar com suspensão por domínio e auto-cura por probe
│   │   ├── ScreenLock/      # estado de bloqueio da tela (edges por notificação + re-read autoritativo) — alimenta a política lock-aware
│   │   └── External/        # integração BetterDisplay: entrada (OSDSource + OSDTranslation) e volta (CommandChannel + CommandTranslation + ScreenBrightnessController); Lunar segue roadmap
│   ├── Coordinator/         # decide o que aparece na tela: hidden / nowPlaying / hud, com prioridade e timers (SleepClock injetável)
│   ├── Windows/             # WindowManager: uma NSPanel por tela; resolve o estilo por display; frame calculado na mão
│   └── Styles/              # skins: Notch, Card, Classic — cada um View + regra de posição/tamanho da janela (+ compartilhados: SurfaceStyleCore — o esqueleto não-visual que toda skin conforma —, SurfaceAnimation, HUDLevelSlider, HUDIndicatorStyle…)
└── CremaTests/              # testes unitários (espelham a estrutura do app)
    └── Mocks/               # fakes das fontes — implementam os mesmos protocolos das fontes reais
```

## Como rodar localmente

```bash
# abrir no Xcode e rodar com ⌘R (scheme Crema)
open Crema.xcodeproj

# ou build via CLI
xcodebuild -project Crema.xcodeproj -scheme Crema -configuration Debug build

# testes (Swift Testing; a CI roda o mesmo em macos-15)
xcodebuild -project Crema.xcodeproj -scheme Crema test

# lint/format como a CI (versões pinadas lá: SwiftLint 0.65.0 --strict, SwiftFormat 0.62.0 --lint)
swiftlint lint --strict
swiftformat --lint .
```

- `xcodebuild test` concorrentes disputam o lock do build-system no DerivedData compartilhado (parece deadlock) — para execuções paralelas, use `-derivedDataPath` isolado. O target de teste é app-hosted e boota o `AppCore` real: os pollers seguram a runloop e o **teardown do host pode pendurar depois de todos os testes reportarem** — o veredito confiável é a linha `Test run with N tests` no log, não o exit do xcodebuild.
- O app é acessório (LSUIElement): não aparece no Dock — procure o ícone na barra de menus.
- **Em Debug, o menu da barra tem a seção Demo** (`DemoMenu`/`DemoSources`, `#if DEBUG`): fontes e atuadores fake dirigindo o pipeline real — dá pra exercitar HUD e now playing sem tocar API de sistema. Nada disso compila em Release.
- **Acessibilidade no primeiro run**: o onboarding explica a necessidade e abre Ajustes do Sistema → Privacidade e Segurança → Acessibilidade; habilite o app ali. Sem a permissão, o app roda degradado (sem captura de teclas) e sinaliza no menu da barra de menus. Em desenvolvimento, assine com um certificado estável — o TCC identifica o binário pela assinatura e rebuilds podem exigir re-conceder a permissão.
- **Convivendo com o BetterDisplay**: se ele estiver instalado com **Settings → Application → Integration → OSD notification** ligado (4.2.1+), o Crema desenha o HUD de brilho a partir da notificação dele — nada a habilitar do lado do Crema. Desligue o OSD próprio do BetterDisplay nesse mesmo painel, ou aparecem duas barras. Sem o BetterDisplay, nada chega e o app segue igual. **Atuar** sobre display externo continua não implementado — ver ROADMAP.md.

## Regra de ouro

**Dados do sistema sobem já traduzidos pro domínio; estado desce puro pras views.** Tudo abaixo é desdobramento disso.

Na prática: toda tradução de formato de fora (dict do MediaRemote, payload do adapter, notificações de sistema) acontece **dentro da fonte**, na borda — acima dela só circulam os tipos do Domínio. No sentido inverso, as views leem estado do Coordinator e devolvem intenção como método; nunca chamam API de sistema nem guardam cópia de domínio.

## Padrões de código

### Nomenclatura

- Swift API Design Guidelines — tipos e protocolos em `UpperCamelCase`, membros em `lowerCamelCase`; um tipo principal por arquivo, com o arquivo nomeado pelo tipo (`NowPlayingSource.swift`).
- Protocolos de contato com o sistema nomeiam a **capacidade** e levam o sufixo `Source`: `NowPlayingSource`, `SystemHUDSource`.
- Implementações nomeiam **tecnologia + capacidade**: `MediaRemoteAdapterNowPlayingSource`, `JXANowPlayingSource`, `BetterDisplayOSDSource` (e `LunarOSDSource`, quando existir).
- Atuadores (executam ações em vez de emitir eventos — ex.: supressão do OSD) seguem o mesmo esquema: protocolo com nome de capacidade, implementação com nome de tecnologia.

### Comentários

- Comentários explicam o **porquê**, não o quê: decisões não óbvias, gotchas de API, contratos entre camadas, rationale de escolhas (ex.: por que um caminho foi descartado). O código já diz o que faz; o comentário diz o que o código não consegue dizer sozinho.
- Nada de decoração: sem ASCII art, sem banners de seção, sem linhas de `===` ou `***`, sem ênfase enfeitada, sem emoji. Um comentário é uma frase objetiva, não um cartaz.
- Não narre o óbvio: nunca comente o que uma linha claramente já expressa. Preferir renomear/reestruturar o código a explicá-lo num comentário.
- Densidade sobre volume: se um bloco precisa de três frases decoradas, provavelmente precisa de uma frase direta. Corte redundância.
- Exceção que **permanece detalhada**: comentários que carregam conhecimento caro e durável — como o cabeçalho de rationale de API privada em `Sources/Brightness/` (frameworks usados, caminhos descartados e por quê, gotchas de ownership/ID) — devem seguir objetivos, mas o **conteúdo fica**; enxugar decoração desses nunca significa apagar o conhecimento.

### Contrato anti-reincidência (comentários e decisões)

Permanente. Um comentário desatualizado é **bug de doc**, não detalhe menor — mente pro próximo leitor com a autoridade de estar ao lado do código. Os críticos de rodadas futuras **cobram este contrato**.

- **Toda mudança de código revisa os comentários do trecho tocado na MESMA mudança.** Não existe "arrumo o comentário depois": se a lógica mudou, o porquê ao lado dela ou está reconfirmado ou está reescrito, no mesmo diff.
- **Comentário novo carrega porquê e contrato, nunca o-que-o-código-faz.** Se a frase parafraseia a linha abaixo, corte-a e, se preciso, renomeie o código. O comentário diz o que o código não consegue dizer sozinho (ver "### Comentários").
- **Referência a doc interno é sempre autossuficiente.** A lição vive **no próprio comentário**; o ID (`docs/DECISIONS.md: J7-estado-do-outro-lado`) é ponteiro de aprofundamento, nunca a única informação — um leitor sem acesso ao doc ainda entende o porquê.
- **Decisão de design nova relevante pra leitor externo = entrada no `docs/DECISIONS.md` na mesma rodada.** A âncora é o ID canônico; o comentário no código aponta pra ela.
- **Vocabulário datado em código shipped é revisão pendente.** Palavras como "spike", "experimento", "temporário", "por enquanto", "novo/agora" num comentário de código que já embarcou envelhecem e mentem — ao encontrar, corrija (descreva o contrato estável, não o momento em que ele nasceu). Exceção de **proveniência**: "spike" que registra _como_ um conhecimento durável foi obtido — validado por um spike de hardware, com o spike já descartado (o cabeçalho de `Sources/Brightness/`) — é histórico permanente, não estado temporário; ali a palavra é o registro da origem, e vale a exceção já protegida em "### Comentários" ("o conteúdo fica").

### Concorrência

- `@MainActor`: Coordinator, WindowManager e todas as views em `Styles/`.
- O Domínio é 100% value types `Sendable` (struct/enum) — atravessa threads sem drama.
- Fontes podem produzir fora da main (processo, notificações, callbacks de sistema); o **consumo** é sempre na main — o Coordinator consome os streams em `Task`s no MainActor.
- Timers de exibição (ex.: revert do HUD) são `Task` canceláveis dormindo sobre o protocolo **`SleepClock`** (clock injetável em `Coordinator/`; produção usa `ContinuousSleepClock`, testes usam clock fake e nunca dormem de verdade) — nunca `Timer`/RunLoop.
- Processos externos long-running/streaming (o adapter Perl hoje; `betterdisplaycli` quando o external existir): leia o stdout via sequência assíncrona (`FileHandle.bytes` ou equivalente) e trate EOF como indisponibilidade. Nunca `waitUntilExit`/`readDataToEndOfFile` na main thread.
- **Toda interação one-shot com subprocesso é limitada no tempo**: espera por `terminationHandler` sem prazo é espera eterna (um filho pendurado travava a seleção da cadeia inteira — auditoria A6). O padrão é corrida pura testável (deadline sobre `SleepClock` + single-resume) + borda fina que na expiração faz `terminate()` escalando a SIGKILL — o filho é abandonado e morto, nunca esperado (`ChildProcessDeadline`).
- **Operação síncrona bloqueante raçada contra deadline roda em `DispatchQueue.global()`, nunca na cooperative pool** (nem `Task.detached`): a pool cooperativa tem largura fixa e não overcommita — órfãos bloqueados acumulam, e o deadline resume na mesma pool, então órfãos suficientes estrangulam o próprio deadline. O GCD global cresce quando threads bloqueiam; um órfão lá nunca rouba capacidade do trabalho vivo (`OSDApplyDeadline`, regra no header). Operações _async_ seguem em task destacada não-estruturada (o padrão do write/S5).

### Fontes (a borda do sistema)

- Todo ponto de contato com o sistema fica atrás de um protocolo (mockável) — inclusive a integração com outro app, que é só mais uma fonte: o `BetterDisplayOSDSource` conforma `SystemHUDSource` como qualquer outra.
- **Layout de `Sources/`**: os protocolos e as fontes compostas genéricas (merge, sampling) moram na **raiz**; cada subdiretório é uma tecnologia com as implementações concretas (a cadeia do now playing — `ChainedNowPlayingSource` — mora em `NowPlaying/`, junto das fontes que encadeia). A lógica interessante da borda é extraída pura e testável — padrão Reconciler/Translation/Conversion (`ScreenLockReconciler`, `AdapterPayloadTranslation`, `VolumeConversion`) — e a borda fina fica só com o contato de sistema.
- **Supressão do OSD é lock-aware**: com a tela bloqueada ou a sessão fora do console, a supressão é **suspensa** sem tocar na preferência do usuário; no unlock, re-engaja se (e só se) a preferência estiver ligada (`SuppressionLockController` sobre `ScreenLockSource`); o `setEngaged(false)` do lock cancela os probes e limpa a suspensão por domínio — o re-engage nasce saudável. Motivo: não há caminho público pra desenhar sobre o lock shield — provado por probes em hardware (docs/internal/LOCKSCREEN-INVESTIGATION.md) — então suprimir ali deixaria o usuário sem nenhum feedback. Na fonte, um edge de notificação **nunca flipa o estado sozinho**: cada edge dispara re-read autoritativo de `CGSessionCopyCurrentDictionary` — e, porque a notificação pode chegar antes de o dict refletir a mudança (o edge lê sessão stale, o reconciler deduplica e o estado travaria), há **settle re-reads** até a leitura assentada emitir a transição perdida. A **cauda periódica** roda **desde a construção** — paridade real com o health-check do tap, que verifica desde o `init` — e cada edge só coloca um **backoff curto** na frente dela para o skew comum sub-segundo. Armar a cauda no launch (não só no primeiro edge) fecha a janela `[launch, primeiro edge)`: se a primeira notificação de lock da sessão for dropada (`DistributedNotificationCenter` é best-effort, sem redundância pra lock simples), a cauda ainda pega o flip em vez de travar `safe` sobre o lock shield sem nenhum edge pra corrigir (docs/DECISIONS.md: settle-rereads — a lição é que backoff finito fecha o skew só probabilisticamente; a cauda desde o init o torna determinístico).
- **Falha de aplicação suspende por domínio, nunca globalmente**: um apply que falha suspende só o canal que falhou (volume / brilho-tela / brilho-teclado; mute cavalga com volume) — as teclas dele voltam ao sistema (feedback nativo) enquanto os outros domínios seguem suprimidos; um probe read-only com backoff (1→16 s, depois 30 s) re-engaja em silêncio na recuperação, e só uma suspensão duradoura com canal presente aparece no menu (probes sem device — troca de AirPods — e probes kicked por tecla nunca escalam). A decisão de consumo é síncrona, por tecla e consistente entre key-down e key-up (`SuppressionDecider`). **Nenhum caminho de falha escreve preferência.** A escalada tem um **eixo de write-health próprio** (`unconfirmedApplyFailures` por domínio), **ortogonal** à suspensão de probe: o probe re-engaja o domínio de forma otimista (limpa a suspensão), mas o contador de write-health **sobrevive** a esse re-engage e só zera em três situações — um **apply verificado** (`confirmWriteHealthy`, o limpador passivo), um **flip de `setEngaged`** (lock/toggle, que nasce saudável) ou o **retry explícito do usuário** (o único caminho que limpa sem um apply verificado). É por isso que um domínio que escreve e falha em looping — vivo o bastante pra passar no probe read-only, mas com o write morto — ainda escala à suspensão duradoura em vez de piscar re-engaje pra sempre (docs/DECISIONS.md: write-health-axis — a lição é que um eixo que zerasse no re-engage do probe mascararia a falha real de escrita).
- **Estado real atrás de fronteira IPC não é auditável por health-check local — recriação preventiva nos edges físicos é o padrão**: o event tap das teclas de mídia pode ficar `enabled`-mas-surdo quando o WindowServer reroteia a entrega (display sleep/wake, hotplug), e o `isValid`/`isEnabled` locais continuam mentindo "vivo" — o poll de health-check não alcança essa classe. A defesa é reinstalar o tap preventivamente em **todos os edges físicos** que podem ter reconfigurado a entrega: os **4 gatilhos** são `screensDidWake`, `didWake`, o edge de unlock (`onUnlocked`) e a troca de topologia de display (`didChangeScreenParameters` — o 4º, um hotplug sem sleep não dispara wake nem lock). `reinstallTap()` é convergente, idempotente e permission-gated (create-after-uninstall, sem porta órfã), então chamar de mais nunca faz mal — e a entrega roda na `.main` pra recriação acontecer na própria thread do tap, sem raçar um evento entregue (docs/DECISIONS.md: preventive-reinstall e J7-estado-do-outro-lado — a lição é que verdade que vive além de XPC/WindowServer se cobre por ação incondicional no edge, não por leitura local).
- **Integração com app vizinho é fonte como qualquer outra, com quatro regras que custaram sonda pra descobrir** (`Sources/External/`, docs/DECISIONS.md: betterdisplay-osd-source): (1) **nome exato, nunca curinga** — o macOS não entrega observação de `DistributedNotificationCenter` com nome `nil`, então um listener curinga é surdo por construção; (2) **um prefixo só** — o BetterDisplay publica o mesmo evento no nome atual e no legado, e assinar os dois dobra tudo; (3) **o payload pode não estar no `userInfo`** — o dele vem como JSON string no `object`; (4) **escala é do vizinho** — `value`/`maxValue` (medido: 0–64), então só a razão é portável. E três regras de escopo, todas com o mesmo porquê — **com o OSD do vizinho desligado, a barra do Crema é o único feedback do usuário**: só emitir para um alvo que o app **consegue atuar** (HUD de display externo teria slider lançando `externalDisplayUnsupported` no primeiro arrasto); **descartar em vez de adivinhar** (payload sem `maxValue` não ganha escala inventada; payload com `lock` não vira barra normal); e, quando o vizinho reporta, **a fonte de tecla local recua** (`standDown()` gasta a janela do gate de origem) — senão, com supressão desligada, a tecla apenas *observada* arma o poll local e as duas fontes desenham para o mesmo toque, com a leitura errada chegando por último.
- **Barra e escrita falam a mesma escala, e quem desenhou recebe o arrasto**: o `SystemHUD` carrega a **autoridade** que o produziu, e o arrasto volta para ela — desenhar o nível *combined* do vizinho e escrever brilho de hardware moveria a tela para outro lugar (medido: 0.625 × 0.504 na mesma tela). Três consequências que valem para qualquer atuador que more noutro processo: (1) **publique o nível antes de escrever** — o slider não tem valor local, então sem eco imediato a barra congela sob o dedo enquanto o round-trip corre; (2) **coalesça latest-wins**, uma escrita em voo — arrasto dispara por frame, e round-trip por frame é enxurrada que resolve fora de ordem; (3) **falha degrada, não morre** — cai para o atuador do sistema no mesmo arrasto, para de perguntar até o vizinho reportar de novo (evidência, nunca timer), e nunca tenta de novo no meio do gesto.
- **Feedback de integração é por evidência, nunca por presença**: o app do vizinho estar rodando não prova que a integração dele está ligada — só um payload entregue prova, e a afirmação morre quando o app termina. O menu confirma quando está recebendo e, quando o vizinho está na frente e mudo, diz **o que fazer**. Identidade de app vizinho se compara por **bundle ID**, nunca pelo nome localizado.
- **Tecla que some pode não ser tap doente, e sim posição na cadeia**: taps de sessão são encadeados e quem **insere por último recebe primeiro** (`.headInsertEventTap`), então um app de brilho que sobe no login junto com o Crema pode ficar à frente e comer as teclas dele — com o tap vivo e entregando as outras (volume passa, brilho não). Antes de suspeitar da própria porta, pergunte quem está na frente dela: `CGGetEventTapList` é a única visão da cadeia vinda **de fora** do processo, lida só na abertura do menu (cada leitura zera as latências min/max de todos os taps do sistema — nunca em poll). O Crema **não disputa a posição** — reinserir em laço é queda de braço decidida por quem mexeu por último, e ir para o `kCGHIDEventTap` vence sempre mas rouba as teclas de todo terceiro que as quer legitimamente; ele **nomeia** quem está à frente e erra para o silêncio (tap listen-only, desabilitado, de máscara disjunta, cadeia sem tap nosso e concorrente sem nome não geram aviso — linha perdida custa um diagnóstico, linha falsa acusa o vizinho). Ver docs/DECISIONS.md: media-key-chain-contention.
- Fonte de eventos expõe `updates: AsyncStream<TipoDeDomínio>` + `isAvailable() async -> Bool`. A tradução (dict do MediaRemote; o JSON do BetterDisplay) acontece **dentro da fonte**, na borda — nunca acima dela. A fonte de now playing recebe também os hints `noteSeek`/`noteSeekFailed` (default no-op em extensão): o comando de seek viaja por canal separado sem caminho de volta, então uma fonte que extrapola posição localmente re-ancora por eles (docs/DECISIONS.md: scrub-grace).
- O Coordinator recebe as fontes **injetadas pelos protocolos**; nunca referencia uma implementação concreta. Os mocks implementam os mesmos protocolos e moram em `CremaTests/Mocks/`.
- Falha em runtime: o stream termina (`finish`) e quem consome reavalia a disponibilidade (refaz a cadeia de fallback). **Indisponibilidade é estado, não erro fatal** — reserve `throws` para operações pontuais (ex.: disparar um comando), não para o fluxo de eventos.
- **Fim de stream = indisponibilidade, sem fantasma irrepresentável**: quando a fonte de mídia termina, o Coordinator descarta o snapshot e desarma o click-invoke. Um failover no meio da cadeia (adapter → JXA) tem a mesma obrigação — nunca deixar um snapshot com controles armados que nenhuma fonte viva consegue representar.

### Fluxo de estado

- Único `@Observable` do app: o **Coordinator**. O estado é o enum `PresentationState` (`hidden` / `nowPlaying` / `hud`), `Equatable`.
- O tick de posição do playback **amostra o relógio, nunca acumula** (a fonte guarda âncora + instante + taxa e cada tique recalcula `posição + idade × taxa`; um tique atrasado ou perdido se corrige sozinho — docs/DECISIONS.md: sample-dont-integrate) e **não passa pelo `state`**: o Coordinator expõe `state` (forma/layout — o que o WindowManager observa pra reposicionar janela) e `nowPlaying` (snapshot vivo, com a posição avançando a cada segundo). Update só de posição escreve só em `nowPlaying`; views leem posição/scrubbing dali. Isso evita disparar o observation do `state` (e um frame pass) uma vez por segundo.
- Views leem `coord.state` e devolvem **intenção** como métodos (`hover(_:)`, play/pause, scrub, slider do HUD). View nunca chama API de sistema, nunca muta domínio, nunca guarda cópia de domínio em `@State` (`@State` só para efêmeros 100% visuais).
- Prioridade e timers moram **só** no Coordinator: HUD interrompe o now playing e reverte ~1,5 s após a última tecla (o timer reinicia a cada toque, como o HUD nativo).
- Skins são **função pura do estado**: cada estilo = uma View + uma regra de frame. A regra de frame recebe valores puros (um `ScreenGeometry` com frame, safe area do topo e larguras das áreas auxiliares) em vez de `NSScreen` — é isso que torna o cálculo da notch testável. O **esqueleto não-visual** das skins (derivação de layout/conteúdo, freeze do empty-boundary, tamanhos por estado, intents) vive uma vez só em `SurfaceStyleCore` (`SurfaceLayoutKind`/`SurfaceLayout`/`SurfaceStyleBody`); a View de cada estilo carrega apenas o corpo visual, o @State de proveniência e delegates de 1 linha que fixam o parâmetro de Metrics — skin nova = conformar e desenhar, nunca recopiar o esqueleto (docs/DECISIONS.md: shared-skin-skeleton).
- A NSPanel de cada estilo real tem **tamanho fixo** no frame máximo do estilo (expandido + folga de overshoot; `windowFrame`, função pura da regra): a janela **nunca redimensiona** — só o conteúdo SwiftUI anima entre os estados dentro dela (design-reference §1.3; coordenar janela AppKit + render SwiftUI na mesma transição foi a origem de uma família inteira de piscadas intermitentes). A regra de frame segue pura e é a fonte de todas as derivações: tamanhos da superfície por estado e — via o retarget do painel a cada apply/size report — as regiões de hover e a **região clicável**, que derivam da MESMA superfície renderizada em todas as skins (clique e hover nunca divergem; docs/DECISIONS.md: hover-follows-the-eye). Cliques fora da superfície visível atravessam a janela — `ignoresMouseEvents` segue o cursor contra o frame justo do estado atual (`SurfaceClickThrough`), então a barra de menus ao lado da fenda continua clicável. O WindowManager é notificado de forma **síncrona** pelo Coordinator (`onPresentationChange`, no `didSet` do estado) para arming de hover e roteamento de cliques acompanharem o estado no mesmo compasso. Na borda, o `NSHostingView` dos painéis usa `sizingOptions = []` — o default (`.standardBounds`) instala constraints que deixariam o SwiftUI redimensionar a janela.
- **Reduce Motion é app-wide**: com a preferência de acessibilidade ligada, nenhuma animação de movimento — geometria, morphs e crossfades que carregam layout assentam secos; fades de opacidade são a substituição permitida. O gate mora num lugar só (`SurfaceAnimation`, parâmetro `reduceMotion`) — nenhuma view decide isso por conta própria.
- **Superfícies sempre dark**: Cartão e Classic pinam `.environment(\.colorScheme, .dark)` **envolvendo** o `vibrantSurface` (o environment alcança o material AppKit; o `VibrancyMaterial` ainda fixa `NSAppearance` por cinto-e-suspensório), como a Notch sempre fez com o preto opaco — uma aparência por superfície, em todos os estados; escopar por branch flipparia a paleta no meio do morph HUD↔now-playing (docs/DECISIONS.md: hud-fixed-dark-palette). Consequência: o accent do artwork usa banda única de brilho.
- **Contratos de animação** (auditados e pinados por teste; detalhe em docs/internal/archive/CONTRACTS-AUDIT.md): (1) travessia de `hidden` — aparecer ou sumir — é **fade de opacidade no rect final**: geometria (frame e raio de canto) nunca viaja através da fronteira vazio↔visível, e a regra governa **todas** as camadas da superfície (frame externo, raio, clip do material, opacidade), não só a mais externa; (2) morphs visível↔visível usam spring **direcional escolhido pelo destino** — open ao expandir, close (criticamente amortecido, sem overshoot contra a barra de menus) ao recolher; (3) animações de valor (nível do slider, troca de símbolo) são **escopadas ao próprio valor** — nunca alcançam o morph da superfície, o frame da janela ou o timing de aparecer/sumir — e suspendem sob drag e sob Reduce Motion.
- Dispatch de estilo em runtime é o **enum `Style`** (conjunto fechado: notch/card/classic — o card substituiu o circular e depois a pílula; um rawValue persistido de estilo removido — "pill", "circular" — degrada pro default, notch, que em display sem fenda resolve pro card; o rawValue é o formato de persistência nas Preferences) — sem type erasure. `PresentationStyle` segue como o contrato que cada estilo implementa; o enum só despacha.
- **Coordinate space**: tudo em coordenadas globais do AppKit (origem no canto inferior-esquerdo do display primário, y pra cima). `NSScreen.frame` entra verbatim no `ScreenGeometry.frame`; as regras de frame devolvem rects nesse mesmo espaço global, aplicados direto em `NSPanel.setFrame` sem conversão nem flip (documentado em `ScreenTranslation`).

### Degradação graciosa (padrão, não exceção)

- Cadeia do now playing: adapter → JXA → feature desligada. Sem crash em nenhum elo; o estado é sinalizado no menu da barra.
- Sem permissão de Acessibilidade: o app roda sem captura de teclas + aviso no menu.
- Sem o BetterDisplay instalado (ou com a integração de OSD dele desligada): nenhuma notificação chega, a fonte fica inerte e todo o resto opera igual — é por isso que ela não tem preferência nenhuma pra ligar ou desligar.

### Capacidade por build-config

- Capacidades que só fazem sentido numa configuração compilam **só nela**: a infra de demo é `#if DEBUG` (`DemoMenu`, `DemoSources`); o updater Sparkle é `#if !DEBUG` (`UpdaterModel` em Debug é uma casca inerte e o item de menu nem compila — evita rodar updater em build de desenvolvimento; o gate é sobre o **código** do updater — o binário do Sparkle.framework embarca em todas as configurações, pois o link SPM não é condicionado por configuração). O source-of-truth é um `static isSupported` de compile-time, e **testes de contrato pinam o comportamento** (`SparkleUpdaterTests`: `isSupported == false` em Debug; feed URL e chave EdDSA presentes no Info.plist; nenhum default de consentimento pré-setado).

### Internacionalização

- **Nunca string literal de UI numa view** — todo texto visível vem do String Catalog (`Crema/Localizable.xcstrings`) via `String(localized:defaultValue:)` (ou `LocalizedStringKey`). Chaves **semânticas** (`menu.quit`, `style.stub.title`), nunca o texto literal como chave; o `defaultValue` é o texto-fonte.
- **Idioma-base: inglês** (chaves e texto-fonte em inglês no código); `pt-BR` é tradução adicional no catálogo. Idiomas configurados no projeto: `en` (source) + `pt-BR`.
- **Formatação de número/data/tempo sempre via `FormatStyle` sensível a locale** (`.formatted()`, `Duration…formatted(.time(…))`, `.percent`) — nunca interpolação manual de dígitos (o separador decimal 0.8 vs 0,8 segue o locale sozinho).
- Dados de mídia (título/artista) não se traduzem — são conteúdo externo; o que se localiza é o chrome da UI e formatos de composição.
- **Disciplina verbatim do catálogo**: toda chave `String(localized:defaultValue:)` existe no `Localizable.xcstrings` com `defaultValue` byte-a-byte idêntico ao valor `en`, `extractionState` manual, chave semântica (não literal) e unidade `pt-BR` traduzida — sem chaves órfãs.
- **Um nome por conceito, em cada idioma**: um estilo/feature usa um único termo em picker, footers, menu e onboarding dentro de cada idioma; os rótulos do picker/aba são a fonte da verdade (Card no `en` / Cartão no `pt-BR`, Now Playing / Tocando Agora).

### Preferências e logging

- Preferências (estilo — chaveado por display, escrito global pela UI —, toggles de supressão e "mostrar now playing aqui" (headless, sem UI ainda), iniciar no login — **intenção** persistida, nunca o estado real: o registro vive no BTM e o macOS o revoga em troca de identidade, então a intenção existe só para detectar a perda e avisar, jamais para re-registrar sozinho; docs/DECISIONS.md: login-item-intent) vivem em `UserDefaults`, atrás de um tipo `Preferences` injetado onde for preciso. A chave estável por display é o **UUID do display** (`CGDisplayCreateUUIDFromDisplayID`) — a tradução displayID→UUID acontece na borda; preferências e domínio só veem o UUID.
- **Defaults conservadores**: uma pref cujo default desejado difere do zero do tipo lê `object(forKey:) as? T ?? default` para distinguir "não setado" do zero; features opt-in nascem desligadas via `bool(forKey:)`.
- Logging via `os.Logger`, sempre construído por `Logger.crema(category:)` (`Crema/App/Logging.swift` — o único lugar que sabe o `subsystem`), com `category` = camada ou fonte (`"NowPlaying"`, `"Windows"`, `"OSD"`). Sem `print`; nunca instanciar `Logger(subsystem:category:)` direto.

### Exemplos

```swift
// ✅ O protocolo fala o vocabulário do domínio; a tradução acontece DENTRO da fonte
protocol SystemHUDSource {
    var updates: AsyncStream<SystemHUD> { get }
    func isAvailable() async -> Bool
}

final class BetterDisplayOSDSource: SystemHUDSource {   // real: Sources/External/
    // o JSON do BetterDisplay é decodificado aqui, na borda (systemIconID 1 =
    // brilho); volume e mudo não sobem, porque o Core Audio já emite por eles
}

// ❌ Formato de fora vazando pra cima
var updates: AsyncStream<[String: Any]>   // dict cru do MediaRemote chegando na UI
func handle(osdJSON: Data)                // Coordinator parseando JSON do BetterDisplay
```

```swift
// ✅ Skin é função pura do estado; intenção volta como método
struct CardView: View {
    let coord: Coordinator
    var body: some View {
        content(for: coord.state)
            .onHover { coord.hover($0) }   // a view reporta; o Coordinator decide
    }
}

// ❌ Segunda fonte de verdade + view falando com o sistema
struct CardView: View {
    @State private var track: NowPlaying?  // cópia local — dessincroniza do Coordinator
    var body: some View {
        artwork
            .onAppear { _ = DistributedNotificationCenter.default() } // fonte disfarçada de view
    }
}
```

```swift
// ✅ Regra de frame é função pura de valores — o cálculo da notch vira teste comum
struct ScreenGeometry {
    let frame: CGRect
    let safeTop: CGFloat        // altura da fenda
    let auxLeft: CGFloat        // largura da área auxiliar esquerda
    let auxRight: CGFloat       // largura da área auxiliar direita
}
func frame(for state: PresentationState, on geo: ScreenGeometry) -> CGRect

// ✅ WindowManager é notificado no didSet e aplica o estado aos painéis na mão
// (região clicável + arming de hover; a janela em si é fixa e nunca redimensiona)
coord.onPresentationChange = { [weak self] in self?.applyFrames() }

// ❌ SwiftUI ditando o tamanho da janela
.frame(width: expanded ? 420 : 220)   // anima a view; a NSPanel fica pra trás
```

## TDD

- Framework: **Swift Testing** (macros `@Test`/`#expect`; exige Xcode 16+ — o deployment target macOS 14 não é afetado).
- Testes em `CremaTests/`, espelhando a estrutura do app; mocks dos protocolos em `CremaTests/Mocks/`.
- Esperas de teste (`eventually`/`eventuallyOffActor`/`waitForSleep`) são **limitadas por relógio de parede e MainActor-fair** — nunca por contagem de yields: um orçamento de slots de scheduler esgota em máquina saturada (o arranque frio da suíte paralela passou por cima de qualquer contagem), enquanto o prazo de parede corre independente de quem tem CPU. O idioma é spin de yields no caminho saudável + backoff de micro-sleeps de 1 ms até o prazo (`TestSupport.boundedWaitDeadline`, 5 s) — essa é a **exceção estreita e deliberada** ao "testes nunca dormem de verdade": timers de produção seguem no `SleepClock`; o micro-sleep é backoff de executor dentro do helper de espera, não sincronização com timer, e dormir libera o ator exatamente para as tasks esperadas. `waitForSleep` é MainActor por fairness FIFO com as tasks que parkam os sleeps (um yield off-actor queima slots no executor global antes de elas rodarem), e todo prazo estourado falha alto na asserção seguinte em vez de pendurar a suíte — o await por continuation sem prazo já deadlockou a suíte inteira (rodada round1-a1-a3).
- **É unitário** (roda sem tocar em API de sistema):
  - Coordinator: transições de estado, prioridade do HUD sobre o now playing, revert por timer, hover — sempre com fontes mockadas.
  - Regra de frame de cada estilo com `ScreenGeometry` fake — incluindo a geometria da notch (com e sem fenda).
  - Decodificação e mapeamento da notificação de OSD (JSON) → `SystemHUD`.
  - Cadeia de fallback do now playing, com disponibilidade controlada pelos mocks (adapter ok / só JXA / nenhum).
  - Degradação graciosa: integração externa ausente não afeta os fluxos essenciais.
- **Não é unitário** (borda fina; validação manual/smoke): processo real do adapter, Core Audio, event tap, OSDUIHelper, DistributedNotificationCenter real. A regra é manter essas bordas finas o bastante pra toda lógica interessante morar acima delas — e ser testável.
- Foco mínimo (checklist vivo):
  - [ ] Coordinator: transições de estado, prioridade do HUD, revert por timer (com fontes mockadas, sem tocar em API de sistema)
  - [ ] Regras de janela (windowFrame) por estilo, incluindo o cálculo da notch
  - [ ] Fallback do now playing quando o adapter não está disponível
  - [ ] Fonte de integração: decodificar a notificação de OSD e mapear pro SystemHUD correto; app funciona normalmente quando a integração está ausente (degradação graciosa)

## Nunca fazer

- Nunca usar outra API de brilho além das validadas por spike (macOS 26 / Apple Silicon) — tela via **DisplayServices** (`DisplayServicesGet/SetBrightness`, dlopen/dlsym) e teclado via **CoreBrightness** `KeyboardBrightnessClient` (dlopen + ObjC runtime), com o ID do teclado **enumerado** (`copyKeyboardBacklightIDs` + `isKeyboardBuiltIn:`), nunca hardcodado; **descartados** (testados, não funcionam neste hardware): CoreDisplay (retorna 1.0 fixo) e IOKit `IODisplayGetFloatParameter` (serviço morto em Apple Silicon). Todo lookup de símbolo/classe privada é checado: nil ⇒ `isAvailable() == false` e a feature degrada sem crash.
- Nunca chamar MRMediaRemoteGetNowPlayingInfo direto (bloqueado no 15.4+) — sempre via mediaremote-adapter, com fallback
- Nunca deixar tipo da Apple (MediaRemote/Core Audio) nem o JSON do BetterDisplay vazar pra camada de view — a tradução pro domínio acontece na borda (regra de ouro); formato de fora acima da fonte acopla a UI à parte frágil do sistema
- Nunca suprimir o OSD nativo sem tornar reversível e opt-in (e nunca deixar o usuário sem controle de volume: consumo de tecla exige aplicar+verificar; falha suspende o **domínio** que falhou e devolve as teclas dele ao sistema, com probe re-engajando na recuperação) — tecla consumida sempre produz feedback: no limite da escala o HUD refresca mostrando o valor clampado, como o nativo faz — e **nenhum caminho de falha escreve a preferência persistida**
- Nunca disputar posição na cadeia de event taps para tomar de volta uma tecla que outro app pegou primeiro — nem reinserindo em laço, nem tapeando no `kCGHIDEventTap`: duas features legítimas podem querer a mesma tecla, e a escolha é do usuário. O Crema nomeia quem está à frente e para por aí
- Nunca acoplar um estilo ao core — skin novo não pode exigir mudança nas Fontes/Domínio/Coordinator
- Nunca atualizar o frame da janela pelo SwiftUI — todo estilo usa janela FIXA (`windowFrame`, só o conteúdo anima); o frame por estado aplicado na mão existe apenas como fallback defensivo para uma futura view que preencha a janela. Nunca reintroduzir setFrame por estado nos estilos
- Nunca tratar a integração BetterDisplay/Lunar como obrigatória — é enhancement opcional; sem ela o app cobre display interno + volume do sistema
- Nunca implementar DDC próprio — o controle de brilho/volume de externo é delegado ao BetterDisplay/Lunar (a leitura já vem pela notificação deles; a escrita segue roadmap)
- Nunca bloquear a main thread esperando processo externo (`waitUntilExit`, `readDataToEndOfFile`) — stdout se lê como stream assíncrono, e EOF significa indisponibilidade
- Nunca escrever teste unitário que toque API de sistema real — fonte real não entra em teste; os mocks implementam os protocolos
- Nunca manter a supressão de OSD engajada com a tela bloqueada ou a sessão fora do console — não há caminho público pra desenhar sobre o lock shield (NO-GO provado por probes em hardware; docs/internal/LOCKSCREEN-INVESTIGATION.md): o usuário ficaria sem nenhum feedback. A suspensão lock-aware nunca altera a preferência persistida
- Nunca pré-setar defaults de consentimento do Sparkle (`SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`) nem compilar o updater em Debug — o consentimento é do próprio Sparkle, e o contrato Debug-sem-updater é pinado por teste (`SparkleUpdaterTests`)

## Gaps conhecidos

- [x] **Testes de espera bounded flakavam sob suíte paralela** — histórico: `ChildProcessDeadlineTests.aHungOperationIsAbandonedAtTheDeadlineAndKilled` e `ChainedNowPlayingSourceTests.firesActiveSourceEndedOnAPromotion` (rodada qualidade4-e-calibragem, 1× cada; reproduzidos sob máquina saturada na rodada re-endereçamento). Fechado em dois vetores, ambos com fix real: (1) PRODUÇÃO — `raceAgainstDeadline` chamava `onDeadline()` (o kill, que desenrola a operação noutra thread) antes de `race.finish(timedOutValue)`, e o finish tardio da operação morta podia vencer o single-resume; o fix comita o valor do timeout ANTES do kill (determinístico). (2) INFRA — as esperas eram limitadas por contagem de yields, que esgota sob saturação; migradas para prazo de relógio de parede com backoff (ver a regra em TDD), e as que dependem de um park usam o idioma advance-dentro-do-poll. Validado com a suíte completa verde sob carga artificial de CPU. Reincidência a partir daqui é vetor novo, não estes.
- [x] **Auto-disengage da supressão era global e persistia a preferência (J5)** — fechado na rodada round1-a1-a3: falha de apply agora suspende **só o domínio afetado** (as teclas dele voltam ao sistema; probe read-only re-engaja na recuperação) e **nenhum caminho de falha escreve preferência** — o único writer de `suppressesNativeOSD` é a ação do usuário, pinado por `OSDSuppressionPrefSacredTests`. A rede de segurança S5 (usuário nunca sem controle) foi preservada por desenho. Aceitação manual pendente (PLAN T10.1). Histórico e mapa de raio: docs/internal/BUG-CLASS-AUDIT.md §A1.

## Decisões em aberto

- [x] **`SWIFT_VERSION = 5.0` no pbxproj × `--swiftversion 6` no `.swiftformat`** — resolvido: projeto elevado ao modo de linguagem Swift 6 (`SWIFT_VERSION = 6.0`; o formatter já o assumia). Custo pontual, provado por build: `withLock` escopado nos `NSLock` usados em contexto async (cadeia do now playing, demo), `T: Sendable` no `SingleResumeRace`, `nonisolated(unsafe)` nos arrays de observers lidos só no `deinit` (bracket de ciclo de vida documentado no local), `nonisolated static let` nas constantes do suppressor e a chave AX literal no lugar do global C sem anotação do SDK; suíte completa verde — 613 testes em 76 suítes (rodada swift6, 2026-07-27).

Nenhuma pendente.
