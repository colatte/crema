# Crema

> Utilitário minimalista de macOS que mostra o now playing perto da notch (ou num card flutuante em telas sem notch) e substitui os HUDs nativos de volume, brilho da tela e brilho do teclado por versões próprias, com estilo selecionável por display.

Use este documento sempre que gerar ou alterar código neste repositório — ele diz **como escrevemos código aqui**: arquitetura, convenções, naming, concorrência e como as camadas conversam. Quando uma decisão de convenção for tomada durante a implementação, registre-a aqui — este documento evolui junto com o código.

## Stack

| Camada                       | Tecnologia                                                                                                                                    |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Linguagem                    | Swift                                                                                                                                         |
| UI e animações               | SwiftUI                                                                                                                                       |
| Janelas e ciclo de vida      | AppKit — NSPanel borderless; app accessory (LSUIElement)                                                                                      |
| Now playing                  | mediaremote-adapter (bridge em Perl) em todas as versões suportadas; fallback via JXA; checagem de disponibilidade — nunca MediaRemote direto |
| Displays externos (roadmap)  | **Não implementado.** Planejado via BetterDisplay (OSD integration API; sentido inverso via betterdisplaycli / URL scheme / App Intents) ou Lunar (socket `lunar listen`); hoje o app cobre só o display interno + volume do sistema — ver ROADMAP.md |
| Distribuição                 | Download direto, fora da Mac App Store; **assinado com certificado self-signed** (identidade de código estável entre versões, então o grant de Acessibilidade persiste; não satisfaz o Gatekeeper — "abrir mesmo assim" no primeiro launch). **Sparkle integrado** (SPM 2.9.4, exact; compilado só em Release via `#if !DEBUG`) — o ciclo de update só opera quando o appcast for publicado (pendência: PLAN T8.4). `scripts/release.sh` também implementa o caminho Developer ID + notarização, aguardando conta Apple Developer — ver ROADMAP.md |
| Alvo                         | macOS 14+ (Sonoma), Apple Silicon e Intel, com e sem notch                                                                                    |

> **Construído vs. roadmap:** a integração com displays externos (BetterDisplay/Lunar) **não está implementada** — é roadmap (ver [ROADMAP.md](ROADMAP.md)); hoje o app cobre o display interno + volume do sistema. O **Sparkle está integrado** no código (Release-only), mas o ciclo de update ainda não opera — falta publicar o appcast; o caminho Developer ID + notarização existe pronto no `release.sh`, aguardando conta Apple Developer. Até lá, o shipping é self-signed ("abrir mesmo assim" no primeiro launch) e a atualização é manual. As menções a displays externos adiante descrevem como a arquitetura os acomoda **quando existirem**, não features atuais.

## Estrutura de pastas

Estrutura de pastas do app, espelhada pelos testes em `CremaTests/`.

```
crema/                       # raiz do repositório
├── README.md                # visão geral pública, instalação, uso, licença
├── ROADMAP.md               # direções futuras (público)
├── CONTRIBUTING.md          # como contribuir
├── LICENSE                  # GPL-3.0
├── CLAUDE.md                # este arquivo — convenções de código
├── docs/                    # docs de pesquisa (público)
│   ├── design-reference.md          # pesquisa: estilos e polish visual
│   ├── osd-suppression-reference.md # pesquisa: supressão do OSD nativo
│   └── internal/            # gitignored (local-only): SPEC.md, PLAN.md, RELEASE-GUIDE.md, auditorias e investigações
├── scripts/
│   └── release.sh           # build + assinatura (ad-hoc / self-signed / Developer ID + notarização) + DMG
├── ThirdParty/
│   └── mediaremote-adapter/ # bridge de now playing vendorizada (BSD-3-Clause)
├── Crema.xcodeproj          # projeto Xcode
├── Crema/                   # código do app
│   ├── App/                 # entry point (LSUIElement), menu da barra, Settings, onboarding de Acessibilidade, Preferences, login item, updater Sparkle (Release-only), política lock-aware da supressão, demo infra (#if DEBUG)
│   ├── Domain/              # tipos próprios do app (NowPlaying, SystemHUD, MediaKey, PresentationState, DisplayUUID) — nada da Apple vaza pra cima
│   ├── Sources/             # camada Fontes: integração com o sistema (a parte frágil); PROTOCOLOS e fontes compostas na raiz, implementações por tecnologia nos subdiretórios
│   │   ├── NowPlaying/      # mediaremote-adapter + fallback JXA + cadeia de disponibilidade (nunca MediaRemote direto)
│   │   ├── Volume/          # volume do sistema (Core Audio)
│   │   ├── Brightness/      # brilho da tela (DisplayServices) e do teclado (CoreBrightness) — ver "Nunca fazer"
│   │   ├── MediaKeys/       # event tap das teclas de mídia (exige permissão de Acessibilidade)
│   │   ├── OSDSuppression/  # supressão do OSD nativo por interceptação de teclas — opt-in, reversível, aplicar+verificar com auto-disengage
│   │   ├── ScreenLock/      # estado de bloqueio da tela (edges por notificação + re-read autoritativo) — alimenta a política lock-aware
│   │   └── External/        # roadmap (placeholder hoje): fonte BetterDisplay/Lunar que traduziria a notificação de OSD (JSON) pro domínio
│   ├── Coordinator/         # decide o que aparece na tela: hidden / nowPlaying / hud, com prioridade e timers (SleepClock injetável)
│   ├── Windows/             # WindowManager: uma NSPanel por tela; resolve o estilo por display; frame calculado na mão
│   └── Styles/              # skins: Notch, Card, Classic — cada um View + regra de posição/tamanho da janela (+ componentes compartilhados: SurfaceAnimation, HUDLevelSlider, HUDIndicatorStyle…)
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

- O app é acessório (LSUIElement): não aparece no Dock — procure o ícone na barra de menus.
- **Em Debug, o menu da barra tem a seção Demo** (`DemoMenu`/`DemoSources`, `#if DEBUG`): fontes e atuadores fake dirigindo o pipeline real — dá pra exercitar HUD e now playing sem tocar API de sistema. Nada disso compila em Release.
- **Acessibilidade no primeiro run**: o onboarding explica a necessidade e abre Ajustes do Sistema → Privacidade e Segurança → Acessibilidade; habilite o app ali. Sem a permissão, o app roda degradado (sem captura de teclas) e sinaliza no menu da barra de menus. Em desenvolvimento, assine com um certificado estável — o TCC identifica o binário pela assinatura e rebuilds podem exigir re-conceder a permissão.
- **Displays externos (roadmap, não implementado)**: hoje o app cobre só o display interno + volume do sistema. O suporte planejado a brilho/volume de monitor externo dependerá de BetterDisplay ou Lunar instalado, com a integração habilitada nos Settings (uma ativa por vez) — ver ROADMAP.md.

## Regra de ouro

**Dados do sistema sobem já traduzidos pro domínio; estado desce puro pras views.** Tudo abaixo é desdobramento disso.

Na prática: toda tradução de formato de fora (dict do MediaRemote, payload do adapter, notificações de sistema) acontece **dentro da fonte**, na borda — acima dela só circulam os tipos do Domínio. No sentido inverso, as views leem estado do Coordinator e devolvem intenção como método; nunca chamam API de sistema nem guardam cópia de domínio.

## Padrões de código

### Nomenclatura

- Swift API Design Guidelines — tipos e protocolos em `UpperCamelCase`, membros em `lowerCamelCase`; um tipo principal por arquivo, com o arquivo nomeado pelo tipo (`NowPlayingSource.swift`).
- Protocolos de contato com o sistema nomeiam a **capacidade** e levam o sufixo `Source`: `NowPlayingSource`, `SystemHUDSource`.
- Implementações nomeiam **tecnologia + capacidade**: `MediaRemoteAdapterNowPlayingSource`, `JXANowPlayingSource` (e, quando a integração externa existir, `BetterDisplayOSDSource` / `LunarOSDSource`).
- Atuadores (executam ações em vez de emitir eventos — ex.: supressão do OSD) seguem o mesmo esquema: protocolo com nome de capacidade, implementação com nome de tecnologia.

### Comentários

- Comentários explicam o **porquê**, não o quê: decisões não óbvias, gotchas de API, contratos entre camadas, rationale de escolhas (ex.: por que um caminho foi descartado). O código já diz o que faz; o comentário diz o que o código não consegue dizer sozinho.
- Nada de decoração: sem ASCII art, sem banners de seção, sem linhas de `===` ou `***`, sem ênfase enfeitada, sem emoji. Um comentário é uma frase objetiva, não um cartaz.
- Não narre o óbvio: nunca comente o que uma linha claramente já expressa. Preferir renomear/reestruturar o código a explicá-lo num comentário.
- Densidade sobre volume: se um bloco precisa de três frases decoradas, provavelmente precisa de uma frase direta. Corte redundância.
- Exceção que **permanece detalhada**: comentários que carregam conhecimento caro e durável — como o cabeçalho de rationale de API privada em `Sources/Brightness/` (frameworks usados, caminhos descartados e por quê, gotchas de ownership/ID) — devem seguir objetivos, mas o **conteúdo fica**; enxugar decoração desses nunca significa apagar o conhecimento.

### Concorrência

- `@MainActor`: Coordinator, WindowManager e todas as views em `Styles/`.
- O Domínio é 100% value types `Sendable` (struct/enum) — atravessa threads sem drama.
- Fontes podem produzir fora da main (processo, notificações, callbacks de sistema); o **consumo** é sempre na main — o Coordinator consome os streams em `Task`s no MainActor.
- Timers de exibição (ex.: revert do HUD) são `Task` canceláveis dormindo sobre o protocolo **`SleepClock`** (clock injetável em `Coordinator/`; produção usa `ContinuousSleepClock`, testes usam clock fake e nunca dormem de verdade) — nunca `Timer`/RunLoop.
- Processos externos long-running/streaming (o adapter Perl hoje; `betterdisplaycli` quando o external existir): leia o stdout via sequência assíncrona (`FileHandle.bytes` ou equivalente) e trate EOF como indisponibilidade. Nunca `waitUntilExit`/`readDataToEndOfFile` na main thread.

### Fontes (a borda do sistema)

- Todo ponto de contato com o sistema fica atrás de um protocolo (mockável) — inclusive a futura integração BetterDisplay/Lunar (roadmap), que seria só mais uma fonte.
- **Layout de `Sources/`**: os protocolos e as fontes compostas genéricas (cadeia, merge, sampling) moram na **raiz**; cada subdiretório é uma tecnologia com as implementações concretas. A lógica interessante da borda é extraída pura e testável — padrão Reconciler/Translation/Conversion (`ScreenLockReconciler`, `AdapterPayloadTranslation`, `VolumeConversion`) — e a borda fina fica só com o contato de sistema.
- **Supressão do OSD é lock-aware**: com a tela bloqueada ou a sessão fora do console, a supressão é **suspensa** sem tocar na preferência do usuário; no unlock, re-engaja se (e só se) a preferência estiver ligada, com o auto-disengage inerte durante a transição (`SuppressionLockController` sobre `ScreenLockSource`). Motivo: não há caminho público pra desenhar sobre o lock shield — provado por probes em hardware (docs/internal/LOCKSCREEN-INVESTIGATION.md) — então suprimir ali deixaria o usuário sem nenhum feedback. Na fonte, um edge de notificação **nunca flipa o estado sozinho**: cada edge dispara re-read autoritativo de `CGSessionCopyCurrentDictionary`.
- Fonte de eventos expõe `updates: AsyncStream<TipoDeDomínio>` + `isAvailable() async -> Bool`. A tradução (dict do MediaRemote; o JSON do BetterDisplay na fonte externa planejada) acontece **dentro da fonte**, na borda — nunca acima dela.
- O Coordinator recebe as fontes **injetadas pelos protocolos**; nunca referencia uma implementação concreta. Os mocks implementam os mesmos protocolos e moram em `CremaTests/Mocks/`.
- Falha em runtime: o stream termina (`finish`) e quem consome reavalia a disponibilidade (refaz a cadeia de fallback). **Indisponibilidade é estado, não erro fatal** — reserve `throws` para operações pontuais (ex.: disparar um comando), não para o fluxo de eventos.
- **Fim de stream = indisponibilidade, sem fantasma irrepresentável**: quando a fonte de mídia termina, o Coordinator descarta o snapshot e desarma o click-invoke. Um failover no meio da cadeia (adapter → JXA) tem a mesma obrigação — nunca deixar um snapshot com controles armados que nenhuma fonte viva consegue representar.

### Fluxo de estado

- Único `@Observable` do app: o **Coordinator**. O estado é o enum `PresentationState` (`hidden` / `nowPlaying` / `hud`), `Equatable`.
- O tick de posição do playback **não passa pelo `state`**: o Coordinator expõe `state` (forma/layout — o que o WindowManager observa pra reposicionar janela) e `nowPlaying` (snapshot vivo, com a posição avançando a cada segundo). Update só de posição escreve só em `nowPlaying`; views leem posição/scrubbing dali. Isso evita disparar o observation do `state` (e um frame pass) uma vez por segundo.
- Views leem `coord.state` e devolvem **intenção** como métodos (`hover(_:)`, play/pause, scrub, slider do HUD). View nunca chama API de sistema, nunca muta domínio, nunca guarda cópia de domínio em `@State` (`@State` só para efêmeros 100% visuais).
- Prioridade e timers moram **só** no Coordinator: HUD interrompe o now playing e reverte ~1,5 s após a última tecla (o timer reinicia a cada toque, como o HUD nativo).
- Skins são **função pura do estado**: cada estilo = uma View + uma regra de frame. A regra de frame recebe valores puros (um `ScreenGeometry` com frame, safe area do topo e larguras das áreas auxiliares) em vez de `NSScreen` — é isso que torna o cálculo da notch testável.
- A NSPanel de cada estilo real tem **tamanho fixo** no frame máximo do estilo (expandido + folga de overshoot; `windowFrame`, função pura da regra): a janela **nunca redimensiona** — só o conteúdo SwiftUI anima entre os estados dentro dela (design-reference §1.3; coordenar janela AppKit + render SwiftUI na mesma transição foi a origem de uma família inteira de piscadas intermitentes). A regra de frame segue pura e é a fonte de todas as derivações: tamanhos da superfície por estado, regiões de hover e a **região clicável**. Cliques fora da superfície visível atravessam a janela — `ignoresMouseEvents` segue o cursor contra o frame justo do estado atual (`SurfaceClickThrough`), então a barra de menus ao lado da fenda continua clicável. O WindowManager é notificado de forma **síncrona** pelo Coordinator (`onPresentationChange`, no `didSet` do estado) para arming de hover e roteamento de cliques acompanharem o estado no mesmo compasso. Na borda, o `NSHostingView` dos painéis usa `sizingOptions = []` — o default (`.standardBounds`) instala constraints que deixariam o SwiftUI redimensionar a janela.
- **Reduce Motion é app-wide**: com a preferência de acessibilidade ligada, nenhuma animação de movimento — geometria, morphs e crossfades que carregam layout assentam secos; fades de opacidade são a substituição permitida. O gate mora num lugar só (`SurfaceAnimation`, parâmetro `reduceMotion`) — nenhuma view decide isso por conta própria.
- **Contratos de animação** (auditados e pinados por teste; detalhe em docs/internal/CONTRACTS-AUDIT.md): (1) travessia de `hidden` — aparecer ou sumir — é **fade de opacidade no rect final**: geometria (frame e raio de canto) nunca viaja através da fronteira vazio↔visível, e a regra governa **todas** as camadas da superfície (frame externo, raio, clip do material, opacidade), não só a mais externa; (2) morphs visível↔visível usam spring **direcional escolhido pelo destino** — open ao expandir, close (criticamente amortecido, sem overshoot contra a barra de menus) ao recolher; (3) animações de valor (nível do slider, troca de símbolo) são **escopadas ao próprio valor** — nunca alcançam o morph da superfície, o frame da janela ou o timing de aparecer/sumir — e suspendem sob drag e sob Reduce Motion.
- Dispatch de estilo em runtime é o **enum `Style`** (conjunto fechado: notch/card/classic — o card substituiu o circular e depois a pílula; um rawValue persistido de estilo removido — "pill", "circular" — degrada pro default, notch, que em display sem fenda resolve pro card; o rawValue é o formato de persistência nas Preferences) — sem type erasure. `PresentationStyle` segue como o contrato que cada estilo implementa; o enum só despacha.
- **Coordinate space**: tudo em coordenadas globais do AppKit (origem no canto inferior-esquerdo do display primário, y pra cima). `NSScreen.frame` entra verbatim no `ScreenGeometry.frame`; as regras de frame devolvem rects nesse mesmo espaço global, aplicados direto em `NSPanel.setFrame` sem conversão nem flip (documentado em `ScreenTranslation`).

### Degradação graciosa (padrão, não exceção)

- Cadeia do now playing: adapter → JXA → feature desligada. Sem crash em nenhum elo; o estado é sinalizado no menu da barra.
- Sem permissão de Acessibilidade: o app roda sem captura de teclas + aviso no menu.
- Sem a integração de displays externos (roadmap; BetterDisplay/Lunar): as funcionalidades essenciais operam normalmente sobre o display interno + volume do sistema.

### Capacidade por build-config

- Capacidades que só fazem sentido numa configuração compilam **só nela**: a infra de demo é `#if DEBUG` (`DemoMenu`, `DemoSources`); o updater Sparkle é `#if !DEBUG` (`UpdaterModel` em Debug é uma casca inerte e o item de menu nem compila — evita rodar updater em build de desenvolvimento). O source-of-truth é um `static isSupported` de compile-time, e **testes de contrato pinam o comportamento** (`SparkleUpdaterTests`: `isSupported == false` em Debug; feed URL e chave EdDSA presentes no Info.plist; nenhum default de consentimento pré-setado).

### Internacionalização

- **Nunca string literal de UI numa view** — todo texto visível vem do String Catalog (`Crema/Localizable.xcstrings`) via `String(localized:defaultValue:)` (ou `LocalizedStringKey`). Chaves **semânticas** (`menu.quit`, `style.stub.title`), nunca o texto literal como chave; o `defaultValue` é o texto-fonte.
- **Idioma-base: inglês** (chaves e texto-fonte em inglês no código); `pt-BR` é tradução adicional no catálogo. Idiomas configurados no projeto: `en` (source) + `pt-BR`.
- **Formatação de número/data/tempo sempre via `FormatStyle` sensível a locale** (`.formatted()`, `Duration…formatted(.time(…))`, `.percent`) — nunca interpolação manual de dígitos (o separador decimal 0.8 vs 0,8 segue o locale sozinho).
- Dados de mídia (título/artista) não se traduzem — são conteúdo externo; o que se localiza é o chrome da UI e formatos de composição.
- **Disciplina verbatim do catálogo**: toda chave `String(localized:defaultValue:)` existe no `Localizable.xcstrings` com `defaultValue` byte-a-byte idêntico ao valor `en`, `extractionState` manual, chave semântica (não literal) e unidade `pt-BR` traduzida — sem chaves órfãs.
- **Um nome por conceito, em cada idioma**: um estilo/feature usa um único termo em picker, footers, menu e onboarding dentro de cada idioma; os rótulos do picker/aba são a fonte da verdade (Card no `en` / Cartão no `pt-BR`, Now Playing / Tocando Agora).

### Preferências e logging

- Preferências (estilo por display, toggles de supressão e "mostrar now playing aqui", iniciar no login) vivem em `UserDefaults`, atrás de um tipo `Preferences` injetado onde for preciso. A chave estável por display é o **UUID do display** (`CGDisplayCreateUUIDFromDisplayID`) — a tradução displayID→UUID acontece na borda; preferências e domínio só veem o UUID.
- **Defaults conservadores**: uma pref cujo default desejado difere do zero do tipo lê `object(forKey:) as? T ?? default` para distinguir "não setado" do zero; features opt-in nascem desligadas via `bool(forKey:)`.
- Logging via `os.Logger`, com `subsystem` = bundle id e `category` = camada ou fonte (`"NowPlaying"`, `"Windows"`, `"OSD"`). Sem `print`.

### Exemplos

```swift
// ✅ O protocolo fala o vocabulário do domínio; a tradução acontece DENTRO da fonte
protocol SystemHUDSource {
    var updates: AsyncStream<SystemHUD> { get }
    func isAvailable() async -> Bool
}

struct BetterDisplayOSDSource: SystemHUDSource {   // fonte externa planejada (roadmap) — ilustra o padrão
    // decodifica o JSON do BetterDisplay aqui, na borda:
    // systemIconID 1 → .brightness · 3 → .volume · 4 → mute
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
- Nunca deixar tipo da Apple (MediaRemote/Core Audio) nem tipo do BetterDisplay (fonte externa planejada) vazar pra camada de view — a tradução pro domínio acontece na borda (regra de ouro); formato de fora acima da fonte acopla a UI à parte frágil do sistema
- Nunca suprimir o OSD nativo sem tornar reversível e opt-in (e nunca deixar o usuário sem controle de volume: consumo de tecla exige aplicar+verificar com auto-desligamento) — e tecla consumida sempre produz feedback: no limite da escala o HUD refresca mostrando o valor clampado, como o nativo faz
- Nunca acoplar um estilo ao core — skin novo não pode exigir mudança nas Fontes/Domínio/Coordinator
- Nunca atualizar o frame da janela pelo SwiftUI — todo estilo usa janela FIXA (`windowFrame`, só o conteúdo anima); o frame por estado aplicado na mão existe apenas como fallback defensivo para uma futura view que preencha a janela. Nunca reintroduzir setFrame por estado nos estilos
- Nunca tratar a integração BetterDisplay/Lunar (roadmap) como obrigatória — é enhancement opcional; sem ela o app cobre display interno + volume do sistema
- Nunca implementar DDC próprio — o controle de brilho/volume de externo é delegado ao BetterDisplay/Lunar (integração planejada)
- Nunca bloquear a main thread esperando processo externo (`waitUntilExit`, `readDataToEndOfFile`) — stdout se lê como stream assíncrono, e EOF significa indisponibilidade
- Nunca escrever teste unitário que toque API de sistema real — fonte real não entra em teste; os mocks implementam os protocolos
- Nunca manter a supressão de OSD engajada com a tela bloqueada ou a sessão fora do console — não há caminho público pra desenhar sobre o lock shield (NO-GO provado por probes em hardware; docs/internal/LOCKSCREEN-INVESTIGATION.md): o usuário ficaria sem nenhum feedback. A suspensão lock-aware nunca altera a preferência persistida
- Nunca pré-setar defaults de consentimento do Sparkle (`SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`) nem compilar o updater em Debug — o consentimento é do próprio Sparkle, e o contrato Debug-sem-updater é pinado por teste (`SparkleUpdaterTests`)

## Gaps conhecidos

- **Auto-disengage da supressão é global e persiste a preferência (J5)** — hoje, qualquer falha de apply num canal (volume, brilho da tela ou do teclado) desengaja a supressão **inteira** e grava `suppressesNativeOSD = false` — a única escrita de preferência do app que não vem de ação direta do usuário. Deliberado até o redesenho do raio (PLAN T10.1; mapa exato de gatilhos e punição em docs/internal/BUG-CLASS-AUDIT.md §A1). Não "corrigir" de passagem: o comportamento é a rede de segurança S5 (o usuário nunca fica sem controle de volume) e qualquer mudança precisa preservar isso.

## Decisões em aberto

- [ ] **`SWIFT_VERSION = 5.0` no pbxproj × `--swiftversion 6` no `.swiftformat`** — as duas configs divergem sobre o modo de linguagem (o formatter assume regras de Swift 6 que o compilador não está aplicando); alinhar: subir o projeto pra Swift 6 ou corrigir o `.swiftformat`?
