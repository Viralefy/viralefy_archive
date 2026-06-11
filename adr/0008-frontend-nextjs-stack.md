# ADR-0008 — Next.js 14 + React + Tailwind como stack frontend padrão

- **Status:** accepted
- **Data:** 2026-06-11
- **Decisores:** Equipe Viralefy
- **Diretriz relacionada:** §3 (linguagens) — não cobre frontend explicitamente
- **Reavaliação:** 2027-06 (anual) ou em pivot de produto

## Contexto e Problem Statement

A diretriz §3 lista Node.js / Go / Rust para **backend**. Frontend não é coberto. Estado atual:

- `viralefy_front/` — storefront público (Next.js 14, App Router, TypeScript, Tailwind, Sentry).
- `viralefy_backoffice/` — admin panel (Next.js 14, App Router, TypeScript, Tailwind, Sentry).
- Testes: Playwright (e2e), Vitest (unit). Lighthouse para perf.
- Telemetria: Sentry (client + server + edge) + OpenTelemetry instrumentação.

Sem ADR formal, este stack já é "padrão de fato".

## Decision Drivers

- **Volume de devs frontend disponível:** Next.js + React tem maior pool no mercado BR.
- **SSR/SEO:** marketplace precisa indexação de páginas de categoria/produto → Next.js App Router cobre.
- **Tailwind:** consistência visual sem CSS-in-JS pesado, build pequeno.
- **Sentry:** observabilidade de erros frontend conforme §16.
- **Compat com OpenAPI:** geração de client TypeScript a partir do `/docs/openapi.yaml` é viável (openapi-typescript).

## Considered Options

### Option A — Next.js 14 + React + Tailwind (status quo)

**Prós:** SSR, SSG, ISR, App Router, ecosistema maduro, Vercel-compatible mas auto-hospedável.
**Contras:** acoplamento ao React; Next.js major upgrades exigem cuidado (App Router quebrou patterns do Pages Router).

### Option B — SvelteKit

**Prós:** menor bundle, mais simples.
**Contras:** pool de devs menor, ecosistema menor de libs de UI.

### Option C — Astro + React islands

**Prós:** ótimo para sites majoritariamente estáticos com pontos de interatividade.
**Contras:** backoffice (alta interatividade) não se beneficia tanto.

### Option D — SPA (React + Vite) sem SSR

**Prós:** mais simples de hospedar.
**Contras:** perde SEO crítico para marketplace.

## Decision Outcome

**Escolhida: Option A — Next.js 14 + React + Tailwind.**

Justificativa:

1. **SEO obrigatório** no storefront (categorias, landing pages por país/idioma → 130 países × 47 idiomas).
2. **Padrão consolidado** na equipe; trocar agora é custo sem ganho claro.
3. **Backoffice e storefront compartilham stack** → reuso de componentes via copy-paste deliberado (ver §7: shared libs proibidas para domínio; UI components copy é aceito).

### Convenções acordadas

- **Versão alvo:** Next.js 14 (App Router), React 18+, TypeScript strict.
- **Estilo:** Tailwind CSS 3+. Sem CSS-in-JS pesado (styled-components, emotion).
- **Estado:** React Context + hooks customizados. Redux/Zustand apenas com justificativa.
- **Forms:** React Hook Form + Zod (validação compartilhada com backend via tipos gerados).
- **Telemetria:** Sentry + OpenTelemetry (`instrumentation.ts`).
- **i18n:** sistema próprio baseado em chave → arquivo `.json` por idioma (não next-intl ainda; reavaliar).
- **Anexo A:** versões correntes documentadas; major upgrade de Next.js (15+) exige ADR-NN específico.

## Triggers para Reavaliação

- Next.js 14 EOL ou breaking changes incompatíveis com nosso fluxo.
- Pivot para mobile-first nativo (React Native, Flutter).
- Backoffice quebra padrão (ex.: precisa ferramenta tipo AdminJS com BFF próprio).

## Action items

- [ ] Documentar versões correntes no Anexo A da diretrizes.md (ou em `viralefy_archive/STACK-VERSIONS.md`).
- [ ] Plano de migração para Next.js 15 quando estável + 6 meses (App Router maduro).
- [ ] Padronizar shared UI patterns entre `viralefy_front` e `viralefy_backoffice` via copy-doc (não shared lib).

## Consequences

### Positivas

- Stack consolidado, novos features rápidos de implementar.
- SEO/SSR/SSG nativo cobre necessidade comercial.
- Sentry + OTel integrados desde o dia 1.

### Negativas

- Versões major do Next.js exigem janela de validação (App Router breaking changes histórico).
- React ecosystem evolui rápido — manter dependências saudáveis é trabalho contínuo (Renovate ajuda).

## Links

- Diretrizes §3 (não cobre frontend)
- `viralefy_front/`
- `viralefy_backoffice/`
- Próximo: ADR específico se/quando migrar para Next.js 15
