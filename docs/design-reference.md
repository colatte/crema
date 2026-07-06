# Referência de design — estilos e polish visual

> Documento de pesquisa que informa a implementação dos estilos (notch, pílula,
> circular, classic) e o polish visual do Crema. **Todos os valores aqui são
> pontos de partida a calibrar visualmente no hardware — não verdades
> absolutas.** Pesquisa realizada em 2026-07-04 (macOS 26 "Tahoe" vigente);
> alvo de referência: MacBook Pro 14" M4 Pro.

## 0. Licenças dos projetos citados — leia antes de abrir qualquer repo

O Crema é escrito do zero. Regra do projeto: **nunca copiar, transcrever ou
adaptar código de terceiros** — nem de projetos copyleft, nem dos permissivos.
Deste documento, usa-se **abordagens, princípios e valores numéricos** (fatos,
não protegidos por copyright), descritos em prosa. O Crema é distribuído sob
GPL-3.0; escrever tudo do zero é independente da licença — mantém o código sem
herança de origem, copyleft ou permissiva.

Licenças verificadas em 2026-07-04 via `api.github.com/repos/OWNER/REPO/license`:

| Projeto                                                       | Licença (SPDX)                 | Tipo         | Uso permitido no Crema                                                    |
| ------------------------------------------------------------- | ------------------------------ | ------------ | ------------------------------------------------------------------------- |
| [Atoll](https://github.com/Ebullioscopic/Atoll)               | **GPL-3.0**                    | ⚠️ Copyleft  | Só inspiração/princípios — **nunca código**                               |
| [boring.notch](https://github.com/TheBoredTeam/boring.notch)  | **GPL-3.0**                    | ⚠️ Copyleft  | Só inspiração/princípios — **nunca código**                               |
| [MewNotch](https://github.com/monuk7735/mew-notch)            | **GPL-3.0**                    | ⚠️ Copyleft  | Só inspiração — é o projeto mais parecido com o Crema; cuidado redobrado  |
| [SlimHUD](https://github.com/AlexPerathoner/SlimHUD)          | **GPL-3.0**                    | ⚠️ Copyleft  | Só inspiração/princípios — **nunca código**                               |
| [NotchDrop](https://github.com/Lakr233/NotchDrop)             | MIT                            | Permissiva   | Referência de leitura (cópia exigiria atribuição; política: não copiar)   |
| [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) | MIT                            | Permissiva   | Referência de leitura; legalmente usável até como dependência SPM         |
| [volumeHUD](https://github.com/dannystewart/volumeHUD)        | MIT                            | Permissiva   | Referência de leitura (valores do bezel clássico)                         |
| [Notchmeister](https://github.com/chockenberry/Notchmeister)  | própria                        | —            | Referência de leitura (geometria da fenda)                                |
| Alcove ([site](https://tryalcove.com))                        | **fechado/comercial** (US$ 17) | Proprietário | Só o comportamento observável do produto; o repo GitHub é apenas releases |

Prática de segurança: **não abrir o código-fonte dos projetos
GPL lado a lado enquanto implementa feature equivalente** — usar este documento
como intermediário.

---

## 1. Geometria da notch (alvo: MBP 14" M4 Pro)

### 1.1 Dimensões

Painel: 14,2", nativo 3024×1964 @ 254 ppi; escala default "looks like"
**1512×982 @ 2x** ([Apple Tech Specs](https://support.apple.com/en-us/121553)).

A fenda física tem ~370×64 **px nativos**; em **points ela varia com o modo de
escala** (por isso a regra do projeto de derivar em runtime, nunca hardcodar):

| Modo de escala         | Altura da fenda (`safeAreaInsets.top`) | Largura aproximada |
| ---------------------- | -------------------------------------- | ------------------ |
| Default (1512×982)     | **32 pt**                              | ~185–200 pt        |
| More Space (1800×1169) | 38 pt                                  | ~220 pt            |
| Larger Text            | 22 pt                                  | ~127 pt            |

Fontes: datapoint real de `safeAreaInsets.top == 32` ([The Swift Den](https://www.answeroverflow.com/m/1145112887048810606));
Notchmeister usa 185×32 / 220×38 / 127×22 pt por modo. Fallbacks escolhidos
pelos apps para telas onde não dá pra medir: 185 pt (boring.notch,
Notchmeister), 180 pt (MewNotch), 160 pt (Atoll, escolha de estilo), 150 pt
(NotchDrop, deliberadamente menor).

**Gotcha central — menu bar ≠ fenda:** a menu bar com notch tem **37 pt** no
modo default (vs 32 pt da fenda) e varia 27/29/34/37/43 pt conforme a escala
([Bjango, medição sistemática](https://bjango.com/articles/designingmenubarextras/)).
Os apps maduros (boring.notch, Atoll, MewNotch) expõem **como preferência** se
o painel casa com a fenda (`safeAreaInsets.top`) ou com a menu bar
(`frame.maxY − visibleFrame.maxY`). Para o Crema: começar casando com a fenda
(nosso `ScreenGeometry.safeTop`), considerar a preferência depois.

### 1.2 APIs

Todas em `NSScreen`, macOS 12+:

- [`safeAreaInsets`](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets)
  — distâncias das bordas em que o conteúdo não fica obscurecido; só `top` é
  não-zero em notebooks com fenda; zero em telas sem obstrução.
- [`auxiliaryTopLeftArea` / `auxiliaryTopRightArea`](https://developer.apple.com/documentation/appkit/nsscreen/3882915-auxiliarytopleftarea)
  — os dois rects _utilizáveis_ que flanqueiam a fenda, **em coordenadas
  globais** (o mesmo espaço de `frame`); `nil` quando não há fenda.

Derivação da fenda (princípio comum a todos os apps estudados):

- Detecção: `safeAreaInsets.top > 0` ⇔ tem fenda.
- Largura: `frame.width − auxLeft.width − auxRight.width` (equivalente: o vão
  de `auxLeft.maxX` a `auxRight.minX`).
- Altura: `safeAreaInsets.top`.
- Rect global: `x = auxLeft.maxX`, `y = frame.maxY − safeAreaInsets.top`. Como
  os rects auxiliares já vêm no espaço global do AppKit, o resultado entra
  direto no `NSPanel.setFrame` — exatamente a convenção de coordenadas do
  CLAUDE.md/`ScreenTranslation`.

### 1.3 Como os apps ancoram a janela (princípios, em prosa)

Padrão consolidado (boring.notch/Atoll, descrito como princípio):

- Painel transparente não-ativante, **nível `.mainMenu + 3`** (acima da menu
  bar), `collectionBehavior` com canJoinAllSpaces + **fullScreenAuxiliary**
  (visível sobre apps fullscreen) + stationary + ignoresCycle.
- Janela **dimensionada para o estado aberto** e ancorada topo-centro
  (x centrado no midX da tela — a fenda é centrada no display; maxY colado em
  `frame.maxY`); o estado fechado é desenhado _dentro_ da janela maior. Isso
  evita re-frame de janela a cada hover — só a view anima.
  - Nota: nosso WindowManager hoje re-aplica frame por estado (regra de frame).
    As duas abordagens são compatíveis; se a animação de janela brigar com a
    do conteúdo, considerar janela fixa no tamanho máximo + view
    animada (princípio do boring.notch), mantendo a regra de frame pura.
- **Alargar a fenda em ~4 pt** no desenho (2 pt por lado, ou −4 de inset):
  o recorte físico tem cantos suavizados; sem a folga aparecem frestas de luz
  (boring.notch/Atoll somam 4 pt; NotchDrop expande 4 pt por lado).
- Multi-display: janela por tela chaveada por **UUID do display** (idêntico à
  nossa convenção); reconciliar em `didChangeScreenParametersNotification`.
- MewNotch usa janela do tamanho da tela inteira com conteúdo posicionado por
  SwiftUI — alternativa que evita re-frames mas exige controle de hit-testing.

### 1.4 Gotchas

- **A fenda é zona morta de pixels e cliques** — o cursor passa por baixo dela
  ([AppleInsider](https://appleinsider.com/articles/21/10/20/macbook-pros-mouse-cursor-moves-behind-camera-notch)).
  Nunca colocar UI interativa dentro do rect físico; só ao redor/abaixo.
- **"Scale to fit below built-in camera"** (Get Info) reescala a tela para um
  modo sem fenda em runtime — mais um motivo para reagir à notificação de
  mudança de parâmetros e nunca cachear geometria.
- **Tahoe:** MewNotch documentou crash do WindowServer ao mover a janela da
  notch para um space privado via SkyLight ([releases](https://github.com/monuk7735/mew-notch/releases))
  — **evitar CGSSpace/SkyLight**; NSPanel com nível alto + collectionBehavior é
  o caminho seguro (o que já fazemos). Há também o bug de login com "Displays
  have separate Spaces" desligado ([BetterDisplay #4752](https://github.com/waydabber/BetterDisplay/discussions/4752)).
- Fullscreen: a menu bar some mas a fenda fica — sem `fullScreenAuxiliary` o
  painel desaparece sobre apps fullscreen.

---

## 2. Timing e animação

### 2.1 Por que springs

[WWDC23 "Animate with springs"](https://developer.apple.com/videos/play/wwdc2023/10158/):
springs **preservam posição e velocidade quando retargetadas** — o caso exato
do hover (mouse entra/sai/volta no meio do voo). Easing fixo "salta" ao
retargetar. Desde iOS 17/macOS 14 o default do SwiftUI já é spring. Guia da
Apple para `bounce`: 0 = criticamente amortecido (default versátil); ~0.15 =
vivacidade sutil; ~0.3 = claramente bouncy; **> 0.4 desaconselhado para UI**.

### 2.2 Valores de referência (convergência das fontes)

Presets da Apple ([doc](<https://developer.apple.com/documentation/swiftui/animation/snappy(duration:extrabounce:)>)):
`.smooth` = bounce 0, `.snappy` = bounce 0.15, `.bouncy` = bounce 0.3 (todos
duration 0.5 default). Conversões úteis: `dampingFraction = 1 − bounce`;
`response ≈ duration`. Defaults clássicos: `.spring()` = 0.55/0.825;
`interactiveSpring()` = 0.15/0.86.

Valores observados (fatos, projetos GPL descritos em prosa):

| Fonte                 | Abrir                                         | Fechar                              | Interativo/hover                                                       |
| --------------------- | --------------------------------------------- | ----------------------------------- | ---------------------------------------------------------------------- |
| boring.notch          | response **0.42** / damping **0.8**           | response **0.45** / damping **1.0** | interactiveSpring 0.38/0.8 (um spring compartilhado p/ frame+conteúdo) |
| Atoll                 | idem boring.notch                             | idem                                | `.bouncy` acelerado 1.2×; micro-interações 0.16–0.2 / 0.5–0.72         |
| DynamicNotchKit (MIT) | notch: `.bouncy(0.4)`; pílula: `.snappy(0.4)` | `.smooth(0.4)`                      | hover `.snappy(0.4)`                                                   |

**Síntese:** abrir com response/duration **0.35–0.45 s** e bounce **0.15–0.3**
(pílula no piso, notch no teto); fechar com **0.4–0.45 s** e bounce **0** —
**nunca bounce no recolhimento** (overshoot contra a borda da tela lê como
instabilidade). O iOS usa mais bounce no Dynamic Island (recriações convergem
em dampingFraction ~0.6), mas o consenso no macOS é conter, porque a superfície
vive ao lado da menu bar estática.

### 2.3 Hover: delay, histerese, recolhimento

Padrão convergente (boring.notch/Atoll, em prosa) + pesquisa de UX:

- **Delay antes de expandir (hover intent): default 0.3 s**, exposto como
  preferência 0–1 s. Implementado como task cancelável (nossa convenção de
  timers já cobre). [Baymard](https://baymard.com/blog/dropdown-menu-flickering-issue)
  recomenda 300–500 ms para hover-menus; apps de notch ficam no piso (300 ms)
  porque a borda superior é alvo de Fitts "infinito".
- **Feedback imediato mesmo com delay**: um crescimento sutil de poucos pontos
  dispara na hora (interactiveSpring ~0.38/0.8); só a expansão completa espera
  o intent — responsividade sem acionamento acidental.
- **Recolher ao sair: debounce de ~100 ms**, também cancelável — re-entrar
  dentro da janela cancela o fechamento (elimina o "piscar" na borda).
- **Histerese espacial de graça**: a fronteira de saída é a superfície
  expandida (maior que a de entrada) — histerese geométrica + temporal.
- **Supressão pós-ação**: janela de ~0.35 s sem hover-open após fechamento
  programático (ex.: HUD assumiu a superfície), senão reabre porque o mouse
  ainda está lá.
- **Recheck ao disparar**: quando o timer expira, revalidar as condições
  (ainda em hover, ainda fechado) antes de abrir.

---

## 3. Liquid Glass (macOS 26 "Tahoe") — a API nativa

### 3.1 SwiftUI (o caminho certo; **não** blur caseiro)

API central: [`glassEffect(_:in:)`](<https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)>)
(**macOS 26.0+**; default `Glass.regular` + shape `Capsule`):

```swift
content.padding().glassEffect()                          // cápsula regular
content.glassEffect(.regular, in: .rect(cornerRadius: 16))
content.glassEffect(.regular.tint(.accentColor).interactive())
```

- [`Glass`](https://developer.apple.com/documentation/swiftui/glass): `.regular`
  (adaptativo — usar em quase tudo), `.clear` (só sobre mídia rica; nunca
  misturar as variantes), `.identity` (desliga condicionalmente); métodos
  `.tint(_:)` (só para significado, não decoração) e `.interactive()`.
- [`GlassEffectContainer`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer):
  agrupa shapes próximas num único sampling pass e habilita blend/morph
  ("glass cannot sample other glass" — WWDC25 323). `glassEffectID(_:in:)` +
  `@Namespace` para morphing entre estados; `glassEffectUnion` para fundir;
  `glassEffectTransition(.materialize)` quando os efeitos estão distantes.
- Botões: [`buttonStyle(.glass)` / `.glassProminent`](https://developer.apple.com/documentation/swiftui/glassbuttonstyle)
  — preferir aos glassEffect manuais em controles clicáveis.
- **Aplicar `glassEffect` por último** na cadeia de modifiers.

Sessões: [Meet Liquid Glass (219)](https://developer.apple.com/videos/play/wwdc2025/219/),
[Build a SwiftUI app with the new design (323)](https://developer.apple.com/videos/play/wwdc2025/323/),
[Build an AppKit app with the new design (310)](https://developer.apple.com/videos/play/wwdc2025/310/);
guia: [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass).

### 3.2 AppKit

[`NSGlassEffectView`](https://developer.apple.com/documentation/appkit/nsglasseffectview)
(macOS 26+): setar **`contentView`** (não sibling) — o glass amarra a geometria
e aplica vibrância ao conteúdo; `cornerRadius` (999 → cápsula), `tintColor`,
`style` (.regular/.clear). [`NSGlassEffectContainerView`](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview)
para merge/performance. Janela precisa de `backgroundColor = .clear` +
`isOpaque = false` (nosso painel já é assim).

### 3.3 Aplicação na pílula/notch do Crema

- O Liquid Glass é, por definição da Apple, o material da **camada funcional
  flutuante acima do conteúdo** — um HUD/pílula é exatamente esse caso.
- **Rota recomendada para o Crema**: manter o painel transparente e aplicar
  `.glassEffect(in:)` **dentro da view SwiftUI** (o WindowManager continua
  dono do frame). Motivos: relatos de `NSGlassEffectView` envolvendo
  `NSHostingView` com conteúdo em branco/tint errado ([cmux #2459](https://github.com/manaflow-ai/cmux/issues/2459));
  e a rota SwiftUI casa com as skins puras.
- **Bordas/highlight vêm de graça** (lensing, reflexo, adaptação claro/escuro)
  — a view **não** desenha stroke/highlight próprios no ramo 26+.
- **Não fazer**: blur/material caseiro por cima/por baixo do glass; glass
  aninhado em glass; glass na camada de conteúdo; excesso de efeitos
  simultâneos (warning literal da doc).
- **Smoke test obrigatório**: há relato de glass degradando para blur simples
  quando o app não está focado ([HWS forums](https://www.hackingwithswift.com/forums/swiftui/glasseffect-in-floating-window-panel/30067))
  — o Crema é LSUIElement e quase nunca é o app ativo; validar no hardware.

### 3.4 Fallback (target macOS 14+)

Todas as APIs de glass são **26.0+, sem back-deployment**. Padrão para as skins:

```swift
if #available(macOS 26.0, *) {
    content.glassEffect(.regular, in: .capsule)
} else {
    content.background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
}
```

O stroke sutil só existe no ramo antigo (no 26+ o sistema desenha o highlight).
Nossas views já usam `.ultraThinMaterial` — o trabalho aqui é embrulhar
isso num modifier de "superfície" com o branch de disponibilidade. Testar com
Reduce Transparency/Reduce Motion (o sistema adapta os dois ramos sozinho).

---

## 4. Os quatro estilos — referência visual

### 4.1 Notch (expande a fenda)

- **Âncora**: fenda real via safe area/aux areas (§1); desenho alargado ~4 pt.
- **Compacto**: a própria fenda (~185×32 pt no default) — conteúdo do HUD
  inline nas áreas auxiliares, **nunca sob o recorte físico**: padrão de 3
  regiões (ícone+label à esquerda, espaçador preto central da largura da
  fenda, valor/progresso à direita), o mesmo layout do Dynamic Island compacto.
- **Expandido**: referência 640×190 pt de conteúdo (+20 pt de respiro para
  sombra) — valores do boring.notch como fato.
- **Raios assimétricos — o princípio central do estilo**: topo menor que a
  base (base ≈ 2× topo) produz o visual de fenda "escorrendo" do hardware.
  Referência: fechado **6 pt topo / 14 pt base**; aberto **19 / 24**.
- **Cantos concêntricos** (regra da Apple): raio interno = raio externo −
  padding; ≤ 0 vira canto reto. iOS 26 formalizou com `ConcentricRectangle`
  ([Livsy](https://livsycode.com/swiftui/concentricrectangle-and-corner-radius-consistency/)).
  Artwork de referência: 90×90 pt (raio 13) aberto, 20×20 pt (raio 4) fechado.
- Organização do expandido (padrão Dynamic Island/Live Activities,
  [HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)):
  leading = artwork, center = título/artista, trailing/bottom =
  controles/progresso; raio expandido de referência no iOS: 44 pt, margens 20 pt.

### 4.2 Pílula (flutuante, telas sem notch)

- **Cápsula sempre**: raio = altura/2, cantos contínuos (squircle,
  `.continuous`), raio nunca excede metade da menor dimensão.
- **Compacto**: 36–44 pt de altura (Dynamic Island compacto ≈ 36–37 pt, ícone
  24 px, texto 15 pt — [Infinum](https://infinum.com/blog/start-designing-for-dynamic-island-and-live-activities/));
  o Atoll usa 185×32 como fato. Nossa `PillMetrics.compact` (240×40) está na
  faixa; calibrar visualmente.
- **Expandido**: referência 640×200 pt (Atoll usa os mesmos tamanhos do notch
  para reusar conteúdo — mesmo truque que nossas skins já fazem).
- Comportamento inspirador: o indicador de volume do iOS 13+ encolhe de pílula
  cheia para linha fina após um instante ([9to5Mac](https://9to5mac.com/2019/06/03/this-is-the-new-volume-indicator-in-ios-13/))
  — dois níveis de presença (interação → persistência mínima).

### 4.3 Circular/radial

Convenção clássica de knobs/gauges de áudio + valores do Atoll (fatos):

- **Anel com fresta na base**: arco de ~**252°** (15%→85% da circunferência,
  começando em 144°) — o gap embaixo é a assinatura do estilo (o `Gauge`
  circular acessório do SwiftUI segue o mesmo desenho).
- **Tudo escala de um único diâmetro**: ícone central = 32% do diâmetro; label
  numérico abaixo = 15%; bolinha indicadora na ponta = 1,45× a espessura do
  traço.
- Ícone adaptativo por contexto (mudo / `speaker.wave.1→3` por faixa de volume
  com thresholds ~0.3/0.8; sol min/max com threshold 0.6) — casa com o nosso
  `HUDPresentation`, que pode ganhar níveis depois.
- Organização: ícone no centro ("o quê"), anel na borda ("quanto"), valor
  numérico abaixo; sombra leve para descolar do fundo.

### 4.4 Classic (bezel nativo pré-Tahoe, repaginado)

O OSD que a Apple **aposentou no Tahoe** (hoje é um slider no canto
superior-direito, criticado — [MacRumors](https://forums.macrumors.com/threads/new-volume-and-brightness-indicators-stress-me-out.2468210/);
isso valida o "classic" como nostalgia deliberada e o próprio mercado de apps
que o restauram: volumeHUD, Hudlum).

Medidas do original (engenharia reversa, [ffried.codes](https://ffried.codes/2018/01/20/the-internals-of-the-macos-hud/)

- recreação MIT [volumeHUD](https://github.com/dannystewart/volumeHUD)):

* **Quadrado 200×200 pt**, centralizado em x, **y = 140 pt do fundo** da tela
  (constante entre displays).
* **Raio de canto 16–19 pt** (o sistema usava 18.0; a recreação usa 16).
* Material translúcido (vibrancy/blur; a recreação usa `regularMaterial`),
  adapta ao dark mode.
* **Ícone ~80 pt** central a ~70% de opacidade; layout vertical ~100 pt para o
  ícone + ~80 pt para a barra; margens horizontais 20 pt.
* **Barra de 16 segmentos** na base (7,5×7,5 pt com 2 pt de espaçamento na
  recreação): preenchidos ~70% de opacidade, vazios ~20%. Detalhe fiel:
  segmentos **mais largos que altos** e preenchimento parcial **por largura**,
  não por opacidade ([Hudlum](https://manytricks.com/blog/?p=6623)); com
  Option+Shift o sistema ajustava em **quartos de segmento** (64 passos —
  [How-To Geek](https://www.howtogeek.com/265487/how-to-adjust-your-macs-volume-in-smaller-increments/)).
* Timing do original: visível ~1,1 s e fade-out de ~0,11 s (recreação); o
  sistema usava fade de 2000 ms via OSDUIHelper com priority 500.
  - Nota: nosso revert atual é 1,5 s — dentro da faixa; o fade curto (~0,1 s)
    é o detalhe a copiar.
* Repaginação sugerida: manter proporções/posição/segmentos e trocar o
  material pelo Liquid Glass (§3) no macOS 26.

---

## 5. Resumo — valores de partida recomendados

**Tudo abaixo é ponto de partida a calibrar visualmente no hardware.**

| Parâmetro                       | Valor de partida                                                                                                | Fonte |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------- | ----- |
| Fenda MBP 14 (default)          | ~185×32 pt — **sempre derivar em runtime** (aux areas + safeTop); fallback cosmético 185 pt                     | §1.1  |
| Alargamento do desenho da fenda | +4 pt de largura (2 pt/lado)                                                                                    | §1.3  |
| Nível de janela (estilo notch)  | `.mainMenu + 3`, canJoinAllSpaces + fullScreenAuxiliary + stationary                                            | §1.3  |
| Spring de abrir                 | response 0.42 / damping 0.8 (notch) · `.snappy(0.4)` (pílula)                                                   | §2.2  |
| Spring de fechar                | response 0.45 / damping 1.0 (ou `.smooth(0.4)`) — **sem bounce**                                                | §2.2  |
| Hover-intent delay              | 0.3 s (preferência 0–1 s), task cancelável + recheck                                                            | §2.3  |
| Hover-out debounce              | ~100 ms, cancelável                                                                                             | §2.3  |
| Supressão pós-fechamento        | ~0.35 s                                                                                                         | §2.3  |
| Liquid glass                    | `.glassEffect(.regular, in:)` dentro da view SwiftUI (26+); `.ultraThinMaterial` + stroke sutil no fallback <26 | §3    |
| Notch: raios                    | fechado 6/14 (topo/base), aberto 19/24; cantos concêntricos p/ conteúdo                                         | §4.1  |
| Notch: expandido                | ~640×190 pt                                                                                                     | §4.1  |
| Pílula                          | cápsula contínua; compacta 36–44 pt de altura; expandida ~640×200 pt                                            | §4.2  |
| Circular                        | anel 252° com gap na base; ícone 32% do ⌀; label 15% do ⌀                                                       | §4.3  |
| Classic                         | 200×200 pt, y=140 do fundo, raio 16–19, ícone 80 pt, 16 segmentos preenchidos por largura, fade ~0,11 s         | §4.4  |

## 6. Fontes completas

**Apple (oficial):** [safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets) · [auxiliaryTopLeftArea](https://developer.apple.com/documentation/appkit/nsscreen/3882915-auxiliarytopleftarea) · [glassEffect](<https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)>) · [Glass](https://developer.apple.com/documentation/swiftui/glass) · [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer) · [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views) · [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview) · [NSGlassEffectContainerView](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview) · [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass) · [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials) · [HIG Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities) · [WWDC23 Animate with springs](https://developer.apple.com/videos/play/wwdc2023/10158/) · [WWDC25 219 Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) · [WWDC25 323 SwiftUI new design](https://developer.apple.com/videos/play/wwdc2025/323/) · [WWDC25 310 AppKit new design](https://developer.apple.com/videos/play/wwdc2025/310/) · [Animation.snappy](<https://developer.apple.com/documentation/swiftui/animation/snappy(duration:extrabounce:)>) · [Animation.bouncy](<https://developer.apple.com/documentation/swiftui/animation/bouncy(duration:extrabounce:)>) · [MBP 14 M4 Tech Specs](https://support.apple.com/en-us/121553)

**Projetos estudados (licenças na §0):** [boring.notch](https://github.com/TheBoredTeam/boring.notch) (GPL) · [Atoll](https://github.com/Ebullioscopic/Atoll) (GPL) · [MewNotch](https://github.com/monuk7735/mew-notch) (GPL) · [SlimHUD](https://github.com/AlexPerathoner/SlimHUD) (GPL) · [NotchDrop](https://github.com/Lakr233/NotchDrop) (MIT) · [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) (MIT) · [volumeHUD](https://github.com/dannystewart/volumeHUD) (MIT) · [Notchmeister](https://github.com/chockenberry/Notchmeister)

**Artigos/medições:** [Bjango — menu bar por escala](https://bjango.com/articles/designingmenubarextras/) · [ffried.codes — internals do HUD](https://ffried.codes/2018/01/20/the-internals-of-the-macos-hud/) · [Hudlum/Many Tricks](https://manytricks.com/blog/?p=6623) · [How-To Geek — 16 segmentos](https://www.howtogeek.com/265487/how-to-adjust-your-macs-volume-in-smaller-increments/) · [Infinum — Dynamic Island specs](https://infinum.com/blog/start-designing-for-dynamic-island-and-live-activities/) · [Baymard — hover delay 300–500ms](https://baymard.com/blog/dropdown-menu-flickering-issue) · [Ondřej Konečný — nested rounded corners](https://www.ondrejkonecny.com/blog/nested-rounded-corners/) · [The Swift Den — safeAreaInsets 32pt](https://www.answeroverflow.com/m/1145112887048810606) · [9to5Mac — volume iOS 13](https://9to5mac.com/2019/06/03/this-is-the-new-volume-indicator-in-ios-13/) · [MacStories — NotchNook/MediaMate](https://www.macstories.net/reviews/notchnook-and-mediamate-two-apps-to-add-a-dynamic-island-to-the-mac/) · [sinasamaki — Dynamic Island recreation](https://www.sinasamaki.com/dynamic-island/) · [Create with Swift — springs](https://www.createwithswift.com/understanding-spring-animations-in-swiftui/) · [GetStream — spring catalog](https://github.com/GetStream/swiftui-spring-animations)
