# QA Rounds — 213 bugs do relatório do Q.A. (2026-06-12)

Lista bruta em [QA-BUGS-2026-06-12.txt](QA-BUGS-2026-06-12.txt) (1140 linhas).

Cada round abaixo agrupa bugs por **causa raiz** (1 fix → muitos bugs).
Marcadores: `🔴 crítico` `🟠 alta` `🟡 média/baixa`. ID = numeração do QA.

---

## Round 0 — Incidente (priorizado por user)

- ✅ **BUG-15** stale rows em plan_prices — 2 rows BTC com drift (likes TikTok 50k/100k). Recomputadas 2026-06-13. Status volta a operational.

---

## Round 1 — Sistêmicos URL/template (1 fix → várias páginas) — ✅ FECHADO 2026-06-13

- ✅ **BUG-3 / BUG-96 / BUG-101 / BUG-26 (parte)** — `/br/recuperacao-de-perfil` agora usa `COPY_RECUP_*` próprio em 8 idiomas (em vez de reaproveitar COPY_SERV_*)
- ✅ **BUG-40 / BUG-83 / BUG-107 / BUG-131-133** — comentários ganham `COPY_COMMENTS_{EN,PT}`; compartilhamentos+saves ganham `COPY_SHARES_{EN,PT}`. Outros idiomas em fallback EN (próximas rounds)
- ✅ **BUG-39 / BUG-122 / BUG-180** — `<html lang>` agora dinâmico via middleware + headers(). `/br` = pt-BR, `/jp` = ja-JP etc. Verificado em prod
- ✅ **BUG-26 / BUG-186 / BUG-187 / BUG-188 / BUG-201 / BUG-210** — 404 page i18n (en/pt/es/fr/de/it/ru), `robots: noindex,nofollow`, sem canonical pra "/", "Browse all services" preserva contexto do mercado lendo `x-pathname`
- ✅ **BUG-51 / BUG-80 / BUG-144** — Footer DISCOVER traduzido (10 links × 7 idiomas: en/pt/es/fr/de/it/ru). Cookie preferences leva `?lang=`
- ⏭️ **BUG-18 / BUG-23 / BUG-38 / BUG-178** — links quebrados `/system-status` etc — verifiquei: footer já aponta pra paths certos (`/status`, `/cities`, `/vs`). QA reportou estado anterior; nada a fazer no front. Prefetch /tickets é um Link normal (rota existe, só não em auth host)
- ⏭️ **BUG-19 / BUG-81 / BUG-212** — "Suporte" leva a `/tickets`. CSS já oculta Header em auth.viralefy.com via `body[data-auth-page]`. Reverificar em prod
- ⏭️ **BUG-78** — produto `saves Instagram` 404 em `/br/salvamentos-instagram`. Saves são parte de `compartilhamentos_*` (DB-level). Próxima round: garantir que produto save tenha category correta
- 🟡 **BUG-189 / BUG-190 / BUG-202** — Help Center descreve fluxo inexistente. Round 6 (não-sistêmico)

---

## Round 2 — Persistência state-global (tema, moeda, mercado)

- 🟠 **BUG-79 / BUG-111 / BUG-119** — theme/currency/market não persistem ao navegar pra contextos fora de `/br` (legal, vs, cities). Voltam ao default
- 🟠 **BUG-10 / BUG-50** — cookie banner reaparece em `auth.viralefy.com` (cookies não compartilham subdomínio; precisa Domain=.viralefy.com)
- 🟡 **BUG-44** — "Preferences cookies" ativos mesmo após "Apenas essenciais"

---

## Round 3 — i18n produtos + UI (afeta 130 mercados)

- 🔴 **BUG-8 / BUG-47 / BUG-77 / BUG-127 / BUG-128 / BUG-129 / BUG-135 / BUG-137 / BUG-140 / BUG-171 / BUG-172 / BUG-173 / BUG-193 / BUG-194 / BUG-195 / BUG-197 / BUG-198 / BUG-199 / BUG-204 / BUG-205 / BUG-209 / BUG-211** — nomes de produtos, subtítulos ("Ideal for testing", "First push") e CTAs ("Buy now", "View details") em inglês em todos os mercados não-US
- 🔴 **BUG-9 / BUG-24 / BUG-34 / BUG-52 / BUG-55 / BUG-167** — fluxo de auth + modal de checkout 100% em inglês em qualquer mercado
- 🟠 **BUG-43** — registro promete "No password required" mas exige senha (msg contraditória)
- 🟠 **BUG-145 / BUG-150 / BUG-45 / BUG-36 / BUG-37 / BUG-123 / BUG-200** — busca/redirect não respeitam mercado atual; raiz não tem geo-redirect
- 🟠 **BUG-25** — registro sem link "Já tenho conta"; login sem texto descritivo "Criar conta"
- 🟡 **BUG-51 / BUG-80 / BUG-138 / BUG-139 / BUG-141 / BUG-142 / BUG-144 / BUG-151 / BUG-156** — Footer DISCOVER em inglês + "Local pricing applied" + cookie badges "NECESSARY/PREFERENCES" + outras palavras soltas
- 🟡 **BUG-49 / BUG-50 / BUG-75 / BUG-89 / BUG-104 / BUG-49 / BUG-118 / BUG-126 / BUG-149** — páginas inteiras sem versão PT-BR: `/pricing`, `/cookie-preferences`, `/vs`, `/cities/sao-paulo`, `/legal/*`
- 🟡 **BUG-13** — navbar duplicada (sticky + original) durante scroll inicial
- 🟡 **BUG-30 / BUG-31** — `/legal/contact?lang=pt` com "Other languages:" em EN + e-mail sem mailto

---

## Round 4 — SEO + structured data + sitemap

- 🟠 **BUG-48** — meta keywords em EN em páginas PT-BR
- 🟠 **BUG-58 / BUG-70** — FAQ JSON-LD menciona "boleto" que não existe no checkout
- 🟠 **BUG-46 / BUG-100** — OG images PT-BR em inglês ("Instagram followers in Brazil")
- 🟠 **BUG-59 / BUG-67** — sitemap sem `<xhtml:link hreflang>`, sitemap.xml prioriza EN antes de PT
- 🟠 **BUG-71-74** — sitemap PT desordenado, curtidas TikTok 50k antes de 5k, seguidores TikTok truncado em 10k, `/br/servicos` ausente
- 🟠 **BUG-90 / BUG-163** — `/cities/sao-paulo` link aponta `/br/instagram-followers` (alias EN sem 301)
- 🔴 **BUG-186 / BUG-201** — página 404 com `robots: index, follow` + canonical pra `/`
- 🟠 **BUG-191 / BUG-192** — JSON-LD raiz duplicado + `lowPrice="1.00"` quando produto mínimo é $2.50
- 🟠 **BUG-175 / BUG-176 / BUG-177** — `og:type=website` em produto, `og:image:alt` ausente, `og:site_name` ausente
- 🟠 **BUG-203** — `WebSite.inLanguage="en"` num site multilingue
- 🟡 **BUG-56** — `robots.txt` bloqueia AI mas tem `Allow: /`; bloqueia `/og/*` pra todos
- 🟡 **BUG-153 / BUG-165** — meta description truncada em case-study + cities/london
- 🟡 **BUG-154 / BUG-181 / BUG-184** — British spelling ("standardised", "behaviour") em site US-English
- 🟡 **BUG-152** — breadcrumb mostra categoria em vez de título em case-study

---

## Round 5 — Acessibilidade + validação forms

- 🔴 **BUG-2 / BUG-53 / BUG-105 / BUG-109** — React #418 hydration mismatch (causa raiz da tela preta no scroll). Texto E HTML mismatch confirmados
- 🔴 **BUG-91** — PIX checkout sem QR code / Chave Pix exibidos (usuário não tem como pagar)
- 🟠 **BUG-60 / BUG-62** — ESC não fecha modal no Step 3; sem botão "Back" no Step 3
- 🟠 **BUG-61 / BUG-64** — Step 3 Stripe mostra upload PIX irrelevante; info "platform receives 2.50 USDT" confusa
- 🟠 **BUG-17** — modal reseta dados ao voltar após erro
- 🟠 **BUG-16 / BUG-29** — handle Instagram aceita inválido; erro "invalid input" genérico sem campo destacado
- 🟠 **BUG-6 / BUG-42 / BUG-158** — login/register aceitam e-mail inválido sem feedback
- 🟠 **BUG-7 / BUG-168** — login sem "Esqueci a senha?"
- 🟠 **BUG-1 / BUG-4** — tela preta no scroll, logo "Viralefy" invisível no light mode
- 🟠 **BUG-20** — slider de quantidade não-linear (mid = max)
- 🟠 **BUG-21** — "Outros pacotes da categoria" exibe só 1 produto
- 🟠 **BUG-22 / BUG-188** — `/legal/about?lang=pt` redireciona pro Help Center; "Browse all services" perde contexto BR
- 🟠 **BUG-27 / BUG-28 / BUG-114 / BUG-115** — países sem bandeira em /Asia + Europe SEPA 2ª linha; nomes em script nativo misturado com PT
- 🟠 **BUG-33 / BUG-116** — campos obrigatórios sem * + recuperação aceita submit sem email
- 🟠 **BUG-65 / BUG-66 / BUG-206 / BUG-207 / BUG-208** — slider sem aria-label, flags sem alt, sem skip-to-content, logo/dark-mode sem aria-label
- 🟠 **BUG-147 / BUG-148** — phone/telegram sem validação de formato
- 🟡 **BUG-44 / BUG-126** — cookie banner contradiz Política ("não exibimos banner")
- 🟡 **BUG-85 / BUG-86 / BUG-87 / BUG-92 / BUG-155 / BUG-169 / BUG-170** — Política não menciona LGPD, Stripe, Abacate Pay; gateway PIX é "Abacate" mas docs dizem "Woovi"
- 🟡 **BUG-103 / BUG-138** — Serviços premium sem nomes em PT
- 🟡 **BUG-93** — botão "Confirm — pay 13.53 BRL" sem R$ e em EN

---

## Round 6 — Bugs pontuais residuais

- 🟡 **BUG-5 / BUG-54 / BUG-68 / BUG-82** — cupom BLACK10 pré-preenchido + "Apply" sem feedback + cupom não existe (cria expectativa falsa)
- 🟡 **BUG-12** — Account recovery R$ 54.100 sem justificativa na listagem
- 🟡 **BUG-32 / BUG-63 / BUG-93** — mix PT/EN em títulos: "100 likes Instagram — Brasil" / URL em PT
- 🟡 **BUG-84** — `/br/compartilhamentos-instagram` mistura shares + saves sem separação
- 🟡 **BUG-94 / BUG-95** — preço TikTok 50K likes $549,90 (não-redondo), TikTok seguidores 25k/50k sem aviso
- 🟡 **BUG-98** — placeholder "Note" PIX mostra hash hex (irrelevante)
- 🟡 **BUG-99** — pricing promete "ETH + 50 assets" mas checkout só 3 métodos
- 🟡 **BUG-110 / BUG-121** — símbolo BTC "Ⓑ" em vez de "₿"
- 🟡 **BUG-112** — `/legal/terms` sem `?lang=pt` mostra EN sem redirect
- 🟡 **BUG-117** — modal moeda título PT mas itens "USDT/USD/EUR/BRL"
- 🟡 **BUG-120** — Turnstile invisível sem fallback se falhar
- 🟡 **BUG-124 / BUG-125 / BUG-160 / BUG-213** — `/vs/*` promete "WhatsApp support 24/7", "Trial from 1 USDT" inexistentes
- 🟡 **BUG-143** — tabela cookies overflow horizontal (coluna T cortada)
- 🟡 **BUG-146** — registro com placeholder "+55..." numa página global
- 🟡 **BUG-152 / BUG-153 / BUG-154 / BUG-164 / BUG-165 / BUG-166 / BUG-181 / BUG-183 / BUG-184 / BUG-185** — cidades thin content, breadcrumb errado, meta truncated, sem preload, sem breadcrumb
- 🟡 **BUG-159 / BUG-161 / BUG-162** — perf: FCP 2.48s, 859KB JS, TTFB 399ms
- 🟡 **BUG-174** — formato numérico misto "1,000 followers" + "1.000 seguidores" no mesmo card
- 🟡 **BUG-179** — FAQ Instagram menciona TikTok
- 🟡 **BUG-185** — sem preload nas fontes/imagens críticas (FCP)
- 🟡 **BUG-196** — `/de` "30 Minutos" em vez de "1 hora" (intencional?)

---

## Progresso

| Round | Done | Total |
|---|---|---|
| 0 | 1 | 1 |
| 1 | 5 grupos = 22 bugs | 7 grupos |
| 2 | 3 grupos = 8 bugs | 3 grupos |
| 3 | 3 grupos = 14 bugs | 11 grupos |
| 4 | 4 grupos = 7 bugs | 14 grupos |
| 5 | 4 grupos = 11 bugs | 18 grupos |
| 6 | 5 grupos = 15 bugs | 21 grupos |
| 7 | 4 grupos = 8 bugs (críticos) | — |

### Bugs fechados ate aqui (86 do QA):

**Round 0**: BUG-15
**Round 1**: BUG-3, 26, 39, 40, 51, 80, 83, 96, 97, 101, 107, 122, 131, 132, 133, 144, 180, 186, 187, 188, 201, 210
**Round 2**: BUG-10, 44, 50, 85, 86, 87, 92, 119, 126, 155
**Round 3**: BUG-8, 43, 47, 77, 103, 127, 128, 129, 135, 138, 139, 171, 172, 173
**Round 4**: BUG-56, 58, 70, 175, 176, 177, 203
**Round 5**: BUG-6, 7, 35, 42, 65, 66, 158, 168, 206
**Round 6**: BUG-9, 16, 21, 24, 29 (parcial), 34, 46, 52, 55 (parcial), 100, 147, 148, 149, 167
**Round 7**: BUG-60, 61, 62, 90, 91, 105, 109, 117, 163
