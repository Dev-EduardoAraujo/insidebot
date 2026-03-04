# InsideBot - Servidor de Licencas (`insidebotcontrol.com.br`)

Este documento fecha a etapa comercial de licenciamento do `InsideBot`.

## 1. Objetivo

O EA valida licenca via:

- `POST https://insidebotcontrol.com.br/api/v1/license/validate`

Com base na resposta, ele:

- libera execucao (`allowed=true`)
- bloqueia por revogacao/expiracao
- aplica janela de graca offline (se configurada no EA)

## 2. Arquivos criados

- `tools/insidebot_license_server.py` (API de licencas)
- `tools/license_admin/index.html` (frontend admin)
- `tools/license_admin/styles.css` (estilo frontend admin)
- `tools/license_admin/app.js` (logica frontend admin)
- `tools/iniciar_insidebot_license_server.ps1` (startup local)
- `tools/gerenciar_insidebot_licencas.ps1` (admin: criar/listar/revogar/renovar)
- `tools/aplicar_release_insidebot.ps1` (seta token/cliente no `InsideBot.mq5`)

## 3. Contrato da API

### 3.1 Validacao (EA)

`POST /api/v1/license/validate`

Request (exemplo):

```json
{
  "token": "TOKEN_CLIENTE",
  "login": "12345678",
  "server": "HantecMarkets-Server",
  "company": "Hantec",
  "name": "Nome da Conta",
  "program": "InsideBot",
  "build": "4750"
}
```

Response (exemplo valido):

```json
{
  "allowed": true,
  "revoked": false,
  "customer_name": "Cliente X",
  "expires_at": "2026-12-31T23:59:59Z",
  "message": "ok",
  "status": "VALID"
}
```

### 3.2 Admin

Header obrigatorio:

- `X-Admin-Key: <SUA_CHAVE_ADMIN>`

Endpoints:

- `GET /api/v1/admin/licenses`
- `GET /api/v1/admin/events`
- `POST /api/v1/admin/license/upsert`
- `POST /api/v1/admin/license/revoke`
- `POST /api/v1/admin/license/extend`

Painel web:

- `GET /admin` (UI para controlar licencas e visualizar eventos)

## 4. Execucao local (teste rapido)

```powershell
$env:INSIDEBOT_LICENSE_ADMIN_KEY = "troque_essa_chave"
python tools\insidebot_license_server.py --host 127.0.0.1 --port 8090
```

Ou:

```powershell
powershell -ExecutionPolicy Bypass -File tools\iniciar_insidebot_license_server.ps1 -AdminKey "troque_essa_chave"
```

Teste:

```powershell
powershell -ExecutionPolicy Bypass -File tools\gerenciar_insidebot_licencas.ps1 -Action health -BaseUrl "http://127.0.0.1:8090"
```

## 5. Fluxo operacional de venda

1. Criar/atualizar licenca no servidor:

```powershell
powershell -ExecutionPolicy Bypass -File tools\gerenciar_insidebot_licencas.ps1 `
  -Action upsert `
  -BaseUrl "http://127.0.0.1:8090" `
  -AdminKey "troque_essa_chave" `
  -Token "TOK_ITALO_001" `
  -CustomerName "Italo" `
  -ExpiresAt "2026-12-31 23:59:59" `
  -AllowedLogins "12345678" `
  -AllowedServers "HantecMarkets-Server"
```

2. Aplicar release no EA para o cliente:

```powershell
powershell -ExecutionPolicy Bypass -File tools\aplicar_release_insidebot.ps1 `
  -Token "TOK_ITALO_001" `
  -Cliente "Italo" `
  -LicenseUrl "https://insidebotcontrol.com.br"
```

3. Compilar `sliced/InsideBot.mq5` e entregar apenas `.ex5`.

4. Renovar/revogar quando necessario:

```powershell
# renovar 30 dias
powershell -ExecutionPolicy Bypass -File tools\gerenciar_insidebot_licencas.ps1 `
  -Action extend -Token "TOK_ITALO_001" -Days 30 `
  -BaseUrl "http://127.0.0.1:8090" -AdminKey "troque_essa_chave"

# revogar
powershell -ExecutionPolicy Bypass -File tools\gerenciar_insidebot_licencas.ps1 `
  -Action revoke -Token "TOK_ITALO_001" `
  -BaseUrl "http://127.0.0.1:8090" -AdminKey "troque_essa_chave"
```

## 6. Publicacao no dominio (producao)

### 6.1 DNS

- Aponte `insidebotcontrol.com.br` para o IP do servidor.

### 6.2 Reverse proxy HTTPS

Use Nginx/Caddy para TLS e proxy para o processo Python em `127.0.0.1:8090`.

Exemplo Nginx:

```nginx
server {
    listen 443 ssl http2;
    server_name insidebotcontrol.com.br;

    ssl_certificate     /etc/letsencrypt/live/insidebotcontrol.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/insidebotcontrol.com.br/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8090;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

Arquivos prontos no repositorio:
- `tools/deploy/insidebot-license.service`
- `tools/deploy/nginx-insidebotcontrol.conf`

Checklist completo (GitHub -> VPS -> HTTPS -> Go-live):
- `docs/InsideBot_DEPLOY_VPS_GITHUB_CHECKLIST.md`
- `docs/InsideBot_DEPLOY_VPS_ONLY_LICENSE_SERVER.md` (somente servidor de licenca na VPS)

## 7. Seguranca minima recomendada

- `INSIDEBOT_LICENSE_ADMIN_KEY` longo e secreto.
- Bloquear acesso admin por IP (firewall/reverse proxy).
- Backup diario do arquivo SQLite (`tools/license_data/licenses.db`).
- Monitorar `validation_events` para detectar abuso.

## 8. Observacoes do EA

- `InsideBot` ja esta apontando por default para:
  - `LicenseServerBaseUrl = "https://insidebotcontrol.com.br"`
- Em conta real, o cliente precisa liberar WebRequest no MT5 para o dominio.
