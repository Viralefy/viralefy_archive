# RUNBOOK — Migração de Comprovantes Base64 → MinIO

Move comprovantes legacy (data:URL base64 em `orders.proof_url`) para o
bucket `viralefy-proofs` no MinIO local, gravando a chave canônica em
`orders.proof_storage_key`. Preserva `proof_url` intocado pra rollback
seguro do código.

> Escopo: prod (`viralefy-app.service` no core). NÃO toca rows com
> `proof_url` http(s) externos (imgur etc.) — esses ficam como estão.

---

## Pré-flight

1. **Backup do Postgres** (obrigatório):
   ```bash
   ssh root@prod
   sudo -u postgres pg_dump viralefy \
     -Fc -f /var/backups/viralefy-pre-proof-migration-$(date +%Y%m%d-%H%M).dump
   ```

2. **Verifica que migration 040 está aplicada**:
   ```bash
   cd /viralefy/core && /usr/local/bin/viralefy-api migrate status \
     | grep 040_proof_storage_key
   ```
   Esperado: `applied`. Caso `pending`, rode `viralefy-api migrate up`
   antes de prosseguir.

3. **Verifica conexão com MinIO + bucket existente**:
   ```bash
   source /etc/viralefy/.env
   docker exec viralefy-storage mc ls local/viralefy-proofs | head
   ```

4. **Conta rows pendentes**:
   ```sql
   SELECT count(*) FROM orders
    WHERE proof_storage_key IS NULL
      AND proof_url LIKE 'data:%';
   ```
   Anote N — esse é o universo de migração.

5. **Build do migrador** (no jumpbox ou na própria VPS):
   ```bash
   cd /viralefy/core
   /usr/local/go/bin/go build -o /usr/local/bin/migrate-proofs ./cmd/migrate-proofs
   ```

---

## Dry-run

Sempre rode primeiro pra validar parsing + tamanhos:

```bash
EnvironmentFile=/etc/viralefy/.env \
  /usr/local/bin/migrate-proofs --dry-run --batch=50
```

Ou via systemd-run pra herdar o env:
```bash
sudo systemd-run --pipe --wait \
  --property=EnvironmentFile=/etc/viralefy/.env \
  /usr/local/bin/migrate-proofs --dry-run --batch=10
```

Sai depois do primeiro batch (não pode loopar — sem update, mesmo WHERE
match infinito). Confirme nos logs:
- `mime` detectado bate com a imagem real;
- `bytes` razoável (~50KB-2MB por proof);
- nenhum `parse data url failed` em massa.

---

## Execução

Limites recomendados pra primeira passada:

```bash
sudo systemd-run --pipe --wait --uid=viralefy --gid=viralefy \
  --property=EnvironmentFile=/etc/viralefy/.env \
  /usr/local/bin/migrate-proofs --execute --batch=50 --limit=200
```

- `--batch=50` mantém lock curto no Postgres.
- `--limit=200` corta após 200 rows pra validar amostra. Remova depois.

Em paralelo, num outro shell, monitore:
```bash
# Erros do migrador
journalctl --user -u 'run-*.service' -f

# Pressão no Postgres
sudo -u postgres psql viralefy -c "
  SELECT count(*) FILTER (WHERE proof_storage_key IS NOT NULL) AS migrated,
         count(*) FILTER (WHERE proof_storage_key IS NULL
                          AND proof_url LIKE 'data:%') AS pending
    FROM orders;"

# MinIO: objetos no bucket
docker exec viralefy-storage mc ls local/viralefy-proofs/proofs | wc -l
```

Sanity check após --limit=200:
- pegue 3 `order_id` migrados aleatórios;
- abra `GET /v1/admin/orders/{id}/proof-url` no backoffice;
- confirme que retorna URL presigned do MinIO (não `data:`).

Depois confiante, rode a passada completa **sem** `--limit`:
```bash
sudo systemd-run --pipe --wait --uid=viralefy --gid=viralefy \
  --property=EnvironmentFile=/etc/viralefy/.env \
  /usr/local/bin/migrate-proofs --execute --batch=50
```

Tempo esperado: ~10ms parse + ~50ms PUT + ~20ms Stat + ~5ms UPDATE = ~85ms
por row. 10k rows ≈ 14min.

---

## Rollback

O migrador NUNCA apaga `proof_url`. Rollback é em camadas:

1. **Reverter app code** (se handlers novos quebraram algo):
   ```bash
   cd /viralefy/core && git checkout <commit-anterior>
   make build && sudo systemctl restart viralefy-app
   ```
   Handlers antigos ignoram `proof_storage_key` e leem `proof_url`
   normalmente — base64 ainda lá.

2. **Reverter migration 040** (só se a coluna em si der problema):
   ```bash
   /usr/local/bin/viralefy-api migrate down 040_proof_storage_key
   ```
   Ou via SQL direto:
   ```sql
   BEGIN;
   DROP INDEX IF EXISTS idx_orders_proof_storage_key;
   ALTER TABLE orders DROP COLUMN IF EXISTS proof_storage_key;
   COMMIT;
   ```
   `proof_url` continua com o base64 — proofs continuam funcionando.

3. **Restaurar dump** (último recurso, perde escritas pós-backup):
   ```bash
   sudo -u postgres pg_restore -d viralefy -c \
     /var/backups/viralefy-pre-proof-migration-*.dump
   ```

---

## Cleanup definitivo (futuro, NÃO faça agora)

Depois de 1 ciclo de release confirmado em prod (≥ 7 dias sem rollback),
podemos esvaziar `proof_url` pros migrados pra recuperar espaço no DB:

```sql
UPDATE orders
   SET proof_url = NULL
 WHERE proof_storage_key IS NOT NULL
   AND proof_url LIKE 'data:%';
```

Isso é uma migration nova (`041_proof_url_cleanup`), não parte dessa.

---

## Métricas de sucesso

- `count(*) FROM orders WHERE proof_url LIKE 'data:%' AND proof_storage_key IS NULL` = 0
- Bucket `viralefy-proofs` tem 1 objeto por row migrada (`mc ls` count)
- Backoffice abre proofs migrados sem erro (`/v1/admin/orders/{id}/proof-url`
  devolve URL `http://127.0.0.1:9000/...?X-Amz-...`)
- `journalctl` do migrador: `failed=0` no log final

---

## Execução em prod 2026-06-10

- **Host**: `root@62.238.41.231` (Debian 13 cloud).
- **Backup**: `/var/backups/viralefy/pre-proof-migration-20260610T073741Z.dump`
  (175 KB, pg_dump custom format — pequeno porque DB está em estágio
  HML/POC com volume mínimo).
- **Migration 040 status pré-execução**: não aplicada. O binário deployado
  em `/usr/local/sbin/viralefy-core` (build de 2026-06-10 00:39) é
  anterior ao commit que adicionou 040, e `viralefy-core migrate status`
  parava em 039. Aplicada manualmente via `psql -f 040_proof_storage_key.up.sql`
  e registrada em `schema_migrations` com checksum
  `3925ed94886aebf5c714622d1479109ed1326dd9385266ed5a38d4fa24bfb92e`
  pra não conflitar com o tracker no próximo deploy do core.
- **Binário do migrador**: buildado local (`go build ./cmd/migrate-proofs`),
  scp pra `/tmp/migrate-proofs`. STORAGE_ENDPOINT=127.0.0.1:9000,
  bucket `viralefy-proofs` (já existente, vazio).
- **Rows pendentes pré-migração**: 0 (`proof_url LIKE 'data:%' AND
  proof_storage_key IS NULL`). Distribuição:
  `null_url=23, data_url=0, http_url=0, total=23`. Não havia
  comprovantes legacy base64 — produção é HML/POC sem orders pagos com
  proof anexado ainda.
- **Dry-run**: `migrated=0 skipped=0 failed=0 duration=4ms`.
- **Execute** (--limit=10 sanity): `migrated=0 skipped=0 failed=0` —
  confirmou conexão MinIO + scan DB OK, no-op por ausência de dados.
- **Rows migradas**: 0.
- **MinIO bucket size pós-execução**: 0 objetos, 0 B.
- **Remaining count**: 0 (objetivo cumprido).
- **Tempo total** (backup → validação final): ~2 min.
- **API check**: skipped (sem rows migradas pra testar
  `/v1/me/orders/{id}/proof-url`). Schema + migrator validados;
  primeira proof real que entrar em produção via novo handler já
  grava `proof_storage_key` direto sem precisar do migrador.

Estado pós-execução: migration 040 ativa, coluna `proof_storage_key`
disponível pra handlers novos, migrador no `/tmp/migrate-proofs` da VPS
pronto pra rerun futuro caso surjam rows base64 (idempotente).
