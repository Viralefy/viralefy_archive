# Memory Index

- [Rodar o stack viralefy local](run-viralefy-stack-local.md) — Go fora do PATH, Postgres em container na 15432, portas dev
- [Correções de build iniciais do stack](viralefy-stack-initial-build-fixes.md) — o commit inicial não compilava; o que estava quebrado e os débitos MVP conhecidos
- [Features v2](viralefy-features-v2.md) — categorias, auth de usuário, autocadastro com senha por e-mail, histórico, multimoeda (display≠cobrança)
- [viralefy_ops e GitHub](viralefy-ops-and-github.md) — installer destrutivo, systemd hardened, 5 repos públicos em github.com/Viralefy
- [Sem nagging sobre rotação de chaves](no-secret-rotation-nag.md) — ambiente HML/POC até ~2026-06-14; usar credenciais sem avisar
- [Manter CONTEXT.md + CHECKLIST.md ao fechar task](maintain-context-md.md) — atualizar/criar os 2 MDs no viralefy_archive após cada task; commit+push; compacta contexto entre sessões
- [Índice §39 é gerado](viralefy-index-generator.md) — viralefy_ops/bin/viralefy-index escreve viralefy_archive/index/; regenerar e commitar junto, senão o CI trava
- [Dívida de doc-comment](viralefy-doc-comment-debt.md) — 61% das funções sem doc de contexto; corrigir na origem por serviço, nunca em massa por IA
