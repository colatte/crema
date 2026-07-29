# Referência — supressão do OSD nativo

> Documento de pesquisa sobre a supressão do HUD nativo de volume/brilho/
> teclado. **Nenhuma técnica aqui exige desabilitar o
> SIP, tocar em /System ou pedir permissões além da Acessibilidade que o Crema
> já usa.** Pesquisa realizada em 2026-07 (macOS 26 "Tahoe" 26.5.2 vigente,
> verificações locais no MBP 14" M4 Pro); fontes citadas por afirmação.
> Constraints: sem SIP off, reversível e opt-in, sem permissões
> perigosas, distribuível.

## 0. Licenças dos projetos citados — leia antes de abrir qualquer repo

Mesma regra do design-reference §0: o Crema é escrito do zero e **nunca copia,
transcreve ou adapta código de terceiros** — nem dos copyleft, nem dos
permissivos. Deste documento usam-se **princípios, fatos e valores** descritos
em prosa.

| Projeto                                                                                                            | Licença (SPDX)                | Tipo         | Uso permitido no Crema                                                      |
| ------------------------------------------------------------------------------------------------------------------ | ----------------------------- | ------------ | --------------------------------------------------------------------------- |
| [SlimHUD](https://github.com/AlexPerathoner/SlimHUD)                                                               | **GPL-3.0**                   | ⚠️ Copyleft  | Só princípios/fatos — **nunca código**                                      |
| [Atoll](https://github.com/Ebullioscopic/Atoll)                                                                    | **GPL-3.0**                   | ⚠️ Copyleft  | Só princípios/fatos — **nunca código**                                      |
| [MewNotch](https://github.com/monuk7735/mew-notch)                                                                 | **GPL-3.0**                   | ⚠️ Copyleft  | Só princípios/fatos — **nunca código**                                      |
| [boring.notch](https://github.com/TheBoredTeam/boring.notch)                                                       | **GPL-3.0**                   | ⚠️ Copyleft  | Só princípios/fatos — **nunca código**                                      |
| [volumeHUD](https://github.com/dannystewart/volumeHUD)                                                             | MIT                           | Permissiva   | **Melhor referência de leitura** (Tahoe-nativa; política: não copiar)       |
| [MonitorControl](https://github.com/MonitorControl/MonitorControl)                                                 | MIT                           | Permissiva   | Referência de leitura (consumo de teclas, repeat, Option+Shift)             |
| [MediaKeyTap](https://github.com/nhurden/MediaKeyTap) (+ [fork MC](https://github.com/MonitorControl/MediaKeyTap)) | MIT                           | Permissiva   | Legalmente usável até como dependência; o Crema já tem tap próprio          |
| [FreeDisplay](https://github.com/huberdf/FreeDisplay)                                                              | MIT                           | Permissiva   | Referência de leitura (teclas de brilho do teclado via tap)                 |
| [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements)                                               | Unlicense                     | Permissiva   | Mecanismo (DriverKit) fora do escopo do Crema; contexto apenas              |
| [Lunar](https://github.com/alin23/Lunar)                                                                           | MIT no repo, app freemium     | ⚠️ Ambígua   | Tratar como source-available; não reusar sem confirmar o componente         |
| [NewBezelServices](https://github.com/MLforAll/NewBezelServices)                                                   | sem licença declarada         | ⚠️ Reservada | Só os fatos de arquitetura (XPC do OSDUIHelper); nada de código             |
| [cleanHUD](https://github.com/w0lfschild/cleanHUD)                                                                 | sem licença (all rights res.) | ⚠️ Reservada | Nada — sem releases desde 2020 e exige SIP off                              |
| [MacForge](https://github.com/MacEnhance/MacForge)                                                                 | MIT                           | Permissiva   | Fora de escopo — exige SIP + Library Validation off; sem releases recentes  |
| MediaMate ([FAQ](https://wouter01.github.io/MediaMate/faq))                                                        | proprietário (Gumroad)        | Proprietário | Só comportamento observável (declara "sem mexer no SIP"; mecanismo fechado) |
| BetterDisplay ([repo](https://github.com/waydabber/BetterDisplay))                                                 | proprietário (repo só issues) | Proprietário | Só issues/wiki                                                              |
| Hudlum ([Many Tricks](https://manytricks.com))                                                                     | proprietário (freeware)       | Proprietário | Só páginas públicas; mecanismo não documentado                              |

## 1. Como o OSD nativo funciona

### 1.1 O pipeline clássico (pré-Tahoe)

- O HUD de volume/brilho/teclado é desenhado pelo **OSDUIHelper.app**
  (`/System/Library/CoreServices/`), que escuta o serviço Mach
  `com.apple.OSDUIHelper` via `NSXPCListener` e implementa o protocolo privado
  `OSDUIHelperProtocol` — método central
  `showImage:onDisplayID:priority:msecUntilFade:withText:` (enum `OSDImage`
  com valores 1–28). O wrapper cliente é o framework privado **OSD.framework**
  (`OSDManager`). Engenharia reversa canônica:
  [ffried.codes, "The internals of the macOS HUD"](https://ffried.codes/2018/01/20/the-internals-of-the-macos-hud/)
  (2018 — os detalhes de renderização **não** valem mais no Tahoe, ver §1.2).
- **Domínio launchd decide o privilégio**: o OSDUIHelper é um **LaunchAgent
  por usuário no domínio gui** (`/System/Library/LaunchAgents/com.apple.OSDUIHelper.plist`:
  `LimitLoadToSessionType [LoginWindow, Aqua]`, `MachServices`,
  `EnablePressuredExit true`), **demand-launched** — não sobe no boot; nasce no
  primeiro pedido de HUD. Por rodar como o usuário logado, um processo comum
  pode dar `launchctl kickstart` e enviar sinais **sem sudo, sem TCC, sem SIP**
  (`kill(2)` permite sinalizar processos do mesmo usuário; verificado
  localmente no 26.5.2).
- Quem **envia** o pedido de OSD não é documentado publicamente; o
  [NewBezelServices](https://github.com/MLforAll/NewBezelServices) documenta
  que o sistema roteia os eventos pro serviço Mach — quem detém o nome recebe.
- A restrição do macOS 14.4 ao `launchctl kickstart -k`
  ([kevinmcox.com](https://www.kevinmcox.com/2024/03/changes-to-launchctl-kickstart-in-macos-14-4/))
  atinge ~153 daemons **de sistema**; o agente gui por usuário não é afetado
  (kickstart em `gui/UID/com.apple.OSDUIHelper` retornou 0 no 26.5.2).

### 1.2 O que mudou no macOS 26 (Tahoe) — o fato que reordena tudo

- O Tahoe substituiu o bezel central de 25 anos por um **popover estilo
  Control Center no canto superior-direito** — a mudança que gerou a leva de
  apps de 2025–26 (volumeHUD, Hudlum, Notchy).
- **O renderer novo é o ControlCenter, não o OSDUIHelper.** Evidência
  (forense local, 26.5.2 build 25F84): o binário do ControlCenter contém
  `ControlCenterApp/SystemBannerService+OSD.swift` e o conjunto completo de
  seletores do `OSDUIHelperProtocol` (inclusive a variante
  `filledChiclets:totalChiclets:locked:` do bezel clássico) — ou seja, o
  ControlCenter implementa ele mesmo o protocolo de OSD. Corroboração de
  ecossistema: o
  [PR #48 do Atoll](https://github.com/Ebullioscopic/Atoll/pull/48)
  ("Works without the OSDUIHelper Disabler… also works on macOS Tahoe") e o
  [volumeHUD](https://github.com/dannystewart/volumeHUD), feito PARA o Tahoe,
  que suprime só por interceptação e nem menciona OSDUIHelper.
- **Correção de forense (2026-07-20, hardware, uid 501).** A leitura original
  desta seção era que o OSDUIHelper ficaria **ocioso** no Tahoe (`state = not
  running` em uso normal) — o que sozinho tornaria o freeze do SlimHUD um no-op.
  A forense de julho/2026 refina o fato **e** prova a conclusão por outro
  caminho: o OSDUIHelper é um agente **demand-launched** — pode estar "not
  running" porque ninguém o invocou, mas quando invocado sobe **vivo, ativo e
  100% freezável/reversível** (kickstart → `state = running`, `endpoint
  active = 1`; SIGSTOP/SIGCONT e SIGKILL+respawn confirmados). A pergunta
  decisiva — *congelá-lo suprime o popover por-tecla do Tahoe?* — foi então
  testada diretamente: com o helper **vivo e congelado** (SIGSTOP), o OSD
  por-tecla **continuou aparecendo normalmente**. Ou seja, "ocioso" era
  impreciso, mas a conclusão da seção (mira o processo errado) **está certa e
  agora provada em hardware**, não apenas inferida das strings.
- Consequência direta: **suspender o OSDUIHelper não suprime o popover do
  Tahoe** (provado pelo smoke acima) — e suspender o renderer real está fora de
  cogitação (o ControlCenter hospeda a barra de menus e tem `KeepAlive`).
- O popover novo é frágil perto de apps de barra de menus: com o BetterDisplay
  rodando, o HUD de volume do Tahoe simplesmente não aparece
  ([BetterDisplay #4726](https://github.com/waydabber/BetterDisplay/issues/4726));
  mesmo sintoma com o Ice ([Ice #719](https://github.com/jordanbaird/Ice/issues/719)).
  Sinal de que a Apple ainda está assentando essa superfície.

## 2. Abordagens descartadas (não recomendar; documentado o porquê)

| Abordagem                                                                                                                  | Por que está morta                                                                                                                                                                                                                                                               |
| -------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `launchctl unload -wF /System/Library/LaunchAgents/com.apple.OSDUIHelper.plist` (ou `com.apple.BezelUI.plist`, pré-Sierra) | Exige **SIP off**; a mudança se perde ao reabilitar o SIP e reiniciar ([SlimHUD discussion #23](https://github.com/AlexPerathoner/SlimHUD/discussions/23))                                                                                                                       |
| `sudo defaults write` nos plists de `/System`                                                                              | Caminho protegido por SIP no macOS moderno; receita da era Sierra                                                                                                                                                                                                                |
| Injeção MacForge/cleanHUD (SIMBL-style)                                                                                    | Exige SIP **e** Library Validation off ([docs do MacEnhance](https://www.macenhance.com/docs/general/sip-sec.html)); incompatível com notarização; sem releases desde 2020/2023                                                                                                  |
| Takeover do serviço Mach (NewBezelServices): registrar o próprio listener em `com.apple.OSDUIHelper`                       | Elegante (receberia TODOS os eventos), mas exige impedir o agente da Apple de reivindicar o nome — operação SIP-protected                                                                                                                                                        |
| `defaults write com.apple.controlcenter EnableSystemBanners -bool false`                                                   | Curiosidade Tahoe (volta o OSD estilo Sequoia; domínio de usuário, reversível — [MonitorControl #1873](https://github.com/MonitorControl/MonitorControl/discussions/1873)), mas é chave privada não documentada e **já não funciona no macOS 27 beta** — não construir sobre ela |

Não existe **nenhuma** API pública, entitlement, toggle de Ajustes ou chave de
defaults suportada para desligar o OSD nativo — inclusive no Tahoe (threads de
usuários pedindo exatamente isso não têm resposta baseada em configuração:
[Apple Discussions](https://discussions.apple.com/thread/256219850),
[MacRumors](https://forums.macrumors.com/threads/new-volume-and-brightness-indicators-stress-me-out.2468210/)).
É por isso que todo app do gênero usa uma das duas técnicas da §3.

## 3. As duas técnicas modernas sem SIP

### 3.1 Interceptação de teclas — consumir o evento no event tap ✅ RECOMENDADA

**Princípio:** o OSD nativo é consequência do sistema PROCESSAR a tecla. Um
`CGEventTap` no nível HID (`kCGHIDEventTap`, opção `.defaultTap`) escutando
eventos `NX_SYSDEFINED` (CGEventType raw 14) decodifica os códigos de tecla
auxiliar do `data1` (soundUp=0, soundDown=1, brightnessUp=2, brightnessDown=3,
mute=7), **engole o evento devolvendo nil do callback** — o sistema nunca vê a
tecla, logo nunca mostra HUD nenhum — e o app **aplica a mudança ele mesmo**
pelos seus atuadores. Quem usa hoje: [volumeHUD 3.0](https://github.com/dannystewart/volumeHUD)
(MIT, nov/2025, feito para o Tahoe — README: "hides the system HUD… by
intercepting the volume/brightness keys and handling changes directly"),
MewNotch (toggle opt-in "System HUD Suppression" desde v2.0.0), boring.notch,
[MonitorControl](https://github.com/MonitorControl/MonitorControl) (MIT, para
displays externos). Também é quase certamente o que o MediaMate faz (fechado;
FAQ só declara "sem mexer no SIP").

**O que o app passa a dever ao usuário** (consumiu a tecla = assumiu o
comportamento inteiro):

- Aplicar o delta: escala nativa de **16 passos**; com **Option+Shift**,
  quartos de passo (**64**) — vale pra volume, brilho da tela E teclado
  ([How-To Geek](https://www.howtogeek.com/265487/how-to-adjust-your-macs-volume-in-smaller-increments/));
  lê-se os modifiers do próprio evento tapado.
- **Key repeat** (tecla segurada): o evento `NX_SYSDEFINED` carrega o flag de
  repeat; tratar como o sistema trata.
- Mute (toggle), teclas de brilho do teclado, e o som de feedback de volume
  quando habilitado nos Ajustes.
- Modo F-key: o tap só vê evento de mídia quando a tecla RESOLVE para mídia —
  o ajuste "Use F1, F2… as standard function keys" é acompanhado de graça
  ([Apple](https://support.apple.com/en-us/102439)).

**Permissões:** Acessibilidade (que o Crema já exige) — o tap de
consumo é o MESMO mecanismo, mudando `.listenOnly` → `.defaultTap`; escuta
global envolve também Input Monitoring (`CGPreflightListenEventAccess`).
Gotcha de desenvolvimento: re-assinar o binário pode deixar o tap **morto em
silêncio** (o TCC reavalia a identidade do código; o tap "existe" mas nada
chega) — re-conceder a permissão resolve
([danielraffel.me](https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/)).

**Reversibilidade: trivial e à prova de crash.** O tap morre com o processo.
Desligar o toggle = parar de consumir; quit/crash/desinstalar = comportamento
nativo restaurado instantaneamente, zero resíduo. É a única técnica em que a
falha catastrófica do app deixa o sistema **exatamente** como era.

**Modo de falha a mitigar:** consumir a tecla e FALHAR em aplicar a mudança
deixa o usuário sem volume/brilho — o boring.notch lançou exatamente esse bug
([#1040](https://github.com/TheBoredTeam/boring.notch/issues/1040)). O padrão
de segurança do volumeHUD (fato externo): após cada tecla interceptada,
verificar se o valor realmente mudou e, se não, autodesabilitar a supressão
inteira até um restart/troca de device.

> **Como o Crema resolve (modelo em vigor, difere do volumeHUD).** O
> auto-desligar global — e persistir a preferência — foi **abolido** (era a
> classe de bug J5). No Crema, apply+verify que falha **suspende só o canal que
> falhou** (volume / brilho-tela / brilho-teclado; mute cavalga com volume): as
> teclas desse canal voltam ao sistema, o feedback nativo reaparece só ali, e os
> outros domínios seguem suprimidos. Um probe read-only com backoff re-engaja em
> silêncio quando o canal se recupera. **Nenhum caminho de falha escreve a
> preferência** — o único writer de "suprimir HUD nativo" é a ação explícita do
> usuário (docs/DECISIONS.md: per-domain-suspension, pref-sacred).

**Limitação estrutural:** só suprime HUDs **originados por tecla**. Mudanças
por slider do Control Center, Siri, coroa/haste de AirPods, brilho automático
etc. não passam pelo teclado — o tap não as vê e o HUD nativo (quando o
sistema decidir mostrá-lo nesses fluxos) aparece. Fato arquitetural
confirmado; o inventário POR GATILHO no Tahoe não está documentado em nenhuma
fonte (o slider do Control Center é feedback visual em si — não está provado
que ele dispare popover adicional). Ver §6, "spike de matriz de gatilhos".

### 3.2 Suspensão do OSDUIHelper (kickstart + SIGSTOP) — pré-Tahoe; hoje complemento questionável

**Princípio (em prosa; SlimHUD desde v1.4.0, jan/2023):** (1) `launchctl
kickstart gui/<uid>/com.apple.OSDUIHelper` força o agente demand-launched a
existir (pode nunca ter nascido — e o kickstart garante um processo FRESCO,
não um no meio de um desenho); (2) espera-se o processo aparecer (SlimHUD
dorme ~500 ms; Atoll faz poll de até 5 s); (3) `killall -STOP OSDUIHelper` o
suspende. Funciona porque **um processo parado continua existindo e ocupando
o job do launchd** — o launchd/XPC não sobe substituto, e o congelado nunca
desenha; as mensagens XPC só enfileiram. Restaurar = `killall -9` (SIGKILL
funciona em processo parado) e o launchd respawna sob demanda. Sem SIP, sem
sudo, sem TCC (sinais a processo do mesmo usuário).

**Por que é frágil (histórico de quem mantém):**

- O sistema **respawna o helper** após sleep/wake, mudança de display/lid e
  jetsam do idle (`EnablePressuredExit`) — o processo novo nasce
  não-suprimido. SlimHUD precisou de release dedicada
  ([v1.5.2](https://github.com/AlexPerathoner/SlimHUD/releases/tag/v1.5.2):
  re-esconder após sleep/monitor/lid + timer de 60 s cujo comentário admite
  que os HUDs "ainda aparecem aleatoriamente"); o Atoll roda **watchdog de
  ~150 ms** re-suspendendo cada PID novo.
- **SIGSTOP no meio de um render congela o HUD nativo na tela**
  ([SlimHUD #159](https://github.com/AlexPerathoner/SlimHUD/issues/159), aberto).
- **Crash/force-quit deixa o helper suspenso** até logout/reboot ou kill
  manual — há relato de HUD nativo que não voltou depois de sair do app
  ([SlimHUD #160](https://github.com/AlexPerathoner/SlimHUD/issues/160); a
  chave `AppleBezelHUDDisabled` citada nesse thread é folclore vindo de
  resposta de IA — não confiar).
- **No Tahoe, mira o processo errado** (§1.2): o popover novo é do
  ControlCenter; suspender o OSDUIHelper vira no-op para o HUD visível. O
  Atoll ainda embarca a técnica, mas o próprio PR #48 comemora funcionar sem
  ela no Tahoe.

**Playbook de reversibilidade** (se algum dia for usada como complemento em
macOS 14/15): restaurar com SIGKILL + respawn (não SIGCONT — melhor um helper
limpo que retomar um possivelmente corrompido); restaurar em todo quit limpo
E toggle-off; re-armar após wake/lid/display-change; watchdog de respawn;
na inicialização, matar qualquer helper suspenso órfão de uma sessão anterior.

## 4. O event tap existente do Crema — o encaixe

O tap de teclas de mídia (`Sources/MediaKeys/`, atrás de protocolo, permissão de
Acessibilidade já pedida no onboarding) é **exatamente o ponto de
interceptação** da técnica recomendada. O que muda em princípio (esboço, sem
código):

1. O tap precisa ser criado com opção de **consumo** (`.defaultTap`) em vez de
   só escuta, e o callback passa a DEVOLVER nil para as teclas cobertas
   **quando a supressão estiver ligada** — desligada, devolve o evento intacto
   (coexistência de dois HUDs, comportamento atual).
2. O fluxo que hoje é "tecla → fonte emite evento → Coordinator mostra HUD
   próprio (e o sistema TAMBÉM aplica e mostra o dele)" vira, com supressão
   ON: "tecla → consumida → atuador do Crema aplica o delta (16/64 passos,
   repeat, mute) → fonte emite → HUD próprio". Os atuadores de volume/brilho
   já existem; o passo novo é o Crema ser o ÚNICO aplicador.
3. **Apply+verify por canal, com suspensão por domínio**: após aplicar,
   confirmar que o valor mudou; falha **suspende só o canal que falhou** (suas
   teclas voltam ao sistema, feedback nativo ali) enquanto os outros domínios
   seguem suprimidos, e um probe read-only re-engaja na recuperação — nunca
   deixar o usuário sem controle de volume, e **nunca escrever a preferência**
   num caminho de falha (docs/DECISIONS.md: per-domain-suspension, pref-sacred).
   O auto-desligar global do modelo antigo (J5) foi abolido.

## 5. Reversibilidade — a história completa

| Cenário                      | Interceptação (recomendada)                         | SIGSTOP (complemento hipotético)                              |
| ---------------------------- | --------------------------------------------------- | ------------------------------------------------------------- |
| Toggle off nos Settings      | Callback devolve os eventos; nativo volta na hora   | SIGKILL + respawn on demand                                   |
| Quit limpo                   | Tap morre com o processo; nativo volta na hora      | Precisa restaurar ANTES de sair (único call site no quit)     |
| **Crash / force-quit**       | **Nativo volta sozinho (tap morre com o processo)** | **Helper fica suspenso até logout/reboot/kill manual** (#160) |
| Desinstalar                  | Zero resíduo                                        | Resíduo até o fim da sessão se não restaurou antes            |
| Sleep/wake, troca de display | Nada a fazer                                        | Re-armar (watchdog + observers)                               |

## 6. Compatibilidade e risco entre versões

- **Essa área quebra a cada ~2 releases**: plists pré-SIP morreram com o SIP;
  unload exigiu SIP off (Big Sur); kickstart+SIGSTOP chegou em 2023; Sequoia
  15.3.x produziu HUD congelado e HUD morto (#159/#160); **Tahoe redesenhou o
  OSD e moveu o renderer**, causando a migração do ecossistema para
  interceptação (volumeHUD/Atoll/MewNotch, 2025–26).
- A interceptação é a técnica **menos acoplada a internals**: depende de
  CGEventTap + NX_SYSDEFINED (API pública estável há décadas, a mesma do
  Karabiner/MonitorControl) e dos atuadores que o Crema já valida por spike.
  O risco recai sobre os atuadores (já mitigado por protocolo + degradação),
  não sobre o mecanismo de supressão.
- **Degradação sã** (o que o Crema faz): supressão **opt-in e feature-flagged**;
  apply+verify com **suspensão por domínio** na falha (a preferência nunca é
  escrita por falha — o modelo de autodesligamento global dos apps maduros foi
  abolido, docs/DECISIONS.md: per-domain-suspension, pref-sacred); sem a
  permissão de Acessibilidade a supressão simplesmente não arma — para o brilho
  o HUD nativo volta a ser o ÚNICO feedback (sem tap não há origem-de-tecla e
  os HUDs próprios de brilho nem surgem; docs/DECISIONS.md:
  key-origin-brightness-gate); no volume, event-driven via Core Audio, os dois
  HUDs coexistem; sinalização no menu da barra só
  para suspensão duradoura com canal presente.
- **Aberto — exige spike de hardware (~30 min)**: a
  matriz de gatilhos residuais no Tahoe (slider do Control Center, Siri,
  AirPods, brilho automático — quais deles mostram o popover nativo com a
  interceptação ligada?) não está documentada em fonte nenhuma; decide se o
  complemento §3.2 tem alguma utilidade real em máquinas pré-Tahoe do público.

## 7. Recomendação e esboço de encaixe (só esboço, sem código)

**Recomendação: interceptação de teclas (§3.1), sozinha.** É a única técnica
que satisfaz as três constraints por construção — sem SIP (API pública +
Acessibilidade já exigida), reversível até sob crash (o tap morre com o
processo), opt-in trivial (flag no callback) — e é a técnica para onde o
ecossistema convergiu no Tahoe. A suspensão do OSDUIHelper fica DOCUMENTADA
(esta página) e descartada como default: no Tahoe mira o processo errado, e
seus modos de falha (HUD congelado, resíduo pós-crash) ferem a constraint de
reversibilidade. Se o spike da §6 mostrar vazamento residual relevante em
macOS 14/15, ela pode voltar como complemento **atrás do mesmo toggle**, com o
playbook da §5 completo.

Encaixe na arquitetura (nomes ilustrativos):

- `Sources/OSDSuppression/` — atuador atrás de protocolo com nome de
  capacidade (ex.: `NativeOSDSuppressing`), implementação
  `EventTapOSDSuppressor` COLABORANDO com a fonte de MediaKeys existente: a
  fonte ganha o modo de consumo; o protocolo expõe ligar/desligar +
  `isAvailable()` (Acessibilidade concedida?). Mock em `CremaTests/Mocks/`.
- O consumo aciona os atuadores existentes de volume/brilho (16/64 passos,
  repeat, mute) — lógica de passos é pura e testável; a borda (tap real)
  continua fina e fora dos testes unitários, como manda o CLAUDE.md.
- `Preferences`: toggle "suprimir HUD nativo" (OFF por padrão, opt-in),
  injetado; menu da barra sinaliza supressão ativa/degradada. **A preferência é
  sagrada**: só a ação do usuário a escreve, nunca um caminho de falha
  (docs/DECISIONS.md: pref-sacred).
- Apply+verify na própria fonte: aplicou → confere → falhou ⇒ **suspende só o
  canal que falhou** (teclas dele voltam ao sistema) e um probe read-only
  re-engaja na recuperação, sem tocar a preferência (docs/DECISIONS.md:
  per-domain-suspension). A supressão é ainda **lock-aware**: com a tela
  bloqueada ela é suspensa (não há caminho público para desenhar sobre o lock
  shield), re-engajando no unlock se a preferência estiver ligada — também sem
  escrever a preferência. Degradação graciosa: sem permissão ⇒ dois HUDs no volume; no brilho, só o nativo (key-origin-brightness-gate).

## 8. Fontes completas

**Internals do pipeline:** [ffried.codes — internals do HUD](https://ffried.codes/2018/01/20/the-internals-of-the-macos-hud/) · [man OSDUIHelper](https://keith.github.io/xcode-man-pages/OSDUIHelper.8.html) · [man kill(2)](https://keith.github.io/xcode-man-pages/kill.2.html) · [kevinmcox — launchctl kickstart no 14.4](https://www.kevinmcox.com/2024/03/changes-to-launchctl-kickstart-in-macos-14-4/) · [9to5Mac — 14.4 e serviços](https://9to5mac.com/2024/04/13/macos-14-4-removes-support-for-commands-that-are-used-to-restart-various-system-services/) · forense local 26.5.2 (strings do ControlCenter; launchctl print; plutil dos LaunchAgents)

**Projetos (licenças na §0):** [SlimHUD](https://github.com/AlexPerathoner/SlimHUD) ([discussion #23](https://github.com/AlexPerathoner/SlimHUD/discussions/23) · [#134](https://github.com/AlexPerathoner/SlimHUD/issues/134) · [#159](https://github.com/AlexPerathoner/SlimHUD/issues/159) · [#160](https://github.com/AlexPerathoner/SlimHUD/issues/160) · [releases](https://github.com/AlexPerathoner/SlimHUD/releases)) · [volumeHUD](https://github.com/dannystewart/volumeHUD) · [Atoll PR #48](https://github.com/Ebullioscopic/Atoll/pull/48) · [MewNotch releases](https://github.com/monuk7735/mew-notch/releases) · [boring.notch #1040](https://github.com/TheBoredTeam/boring.notch/issues/1040) · [MonitorControl](https://github.com/MonitorControl/MonitorControl) ([discussion #1873](https://github.com/MonitorControl/MonitorControl/discussions/1873)) · [MediaKeyTap](https://github.com/nhurden/MediaKeyTap) · [NewBezelServices](https://github.com/MLforAll/NewBezelServices) · [cleanHUD](https://github.com/w0lfschild/cleanHUD) · [MacForge/docs SIP](https://www.macenhance.com/docs/general/sip-sec.html) · [BetterDisplay #966](https://github.com/waydabber/BetterDisplay/issues/966) · [#4726](https://github.com/waydabber/BetterDisplay/issues/4726) · [Ice #719](https://github.com/jordanbaird/Ice/issues/719) · [MediaMate FAQ](https://wouter01.github.io/MediaMate/faq)

**Comportamento de teclas/UX:** [Apple — teclas de função](https://support.apple.com/en-us/102439) · [How-To Geek — 64 passos](https://www.howtogeek.com/265487/how-to-adjust-your-macs-volume-in-smaller-increments/) · [danielraffel — tap silencioso pós re-assinatura](https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/) · [MacRumors — OSD do Tahoe](https://forums.macrumors.com/threads/new-volume-and-brightness-indicators-stress-me-out.2468210/) · [Apple Discussions](https://discussions.apple.com/thread/256219850)
