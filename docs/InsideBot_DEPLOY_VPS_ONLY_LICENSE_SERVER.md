# InsideBot - Deploy VPS (somente servidor de licenca, via GitHub)

Objetivo: manter **apenas** o servidor de validacao de licenca na VPS, sem deploy do projeto inteiro.

## 1) Preencher variaveis (uma vez, no terminal local)

No terminal local (PowerShell), ajuste estes valores:

```powershell
$VPS_IP = "SEU_IP_DA_VPS"
$VPS_USER = "root"                 # ou ubuntu/deploy
$GH_REPO = "git@github.com:SEU_USUARIO/SEU_REPO.git"
$GH_BRANCH = "main"
$CERTBOT_EMAIL = "seu-email@dominio.com"
$ADMIN_KEY = "TROQUE_POR_UMA_CHAVE_FORTE_32+"
$ADMIN_ALLOWED_IP = "206.42.35.148"
```

## 2) Enviar codigo para GitHub (local -> remoto)

No seu projeto local, garanta que os arquivos do servidor estao commitados:

```powershell
git add tools/insidebot_license_server.py tools/license_admin tools/deploy/minimal docs/InsideBot_DEPLOY_VPS_ONLY_LICENSE_SERVER.md
git commit -m "insidebot: deploy minimal license server on VPS"
git push origin main
```

Se voce usa branch diferente, ajuste no passo 3.1 (`GH_BRANCH`).

## 3) Acessar VPS

```bash
ssh VPS_USER@VPS_IP
```

## 3.1) Definir variaveis dentro da VPS

```bash
GH_REPO="git@github.com:SEU_USUARIO/SEU_REPO.git"
GH_BRANCH="main"
CERTBOT_EMAIL="seu-email@dominio.com"
ADMIN_KEY="TROQUE_POR_UMA_CHAVE_FORTE_32+"
ADMIN_ALLOWED_IP="206.42.35.148"
```

## 4) Preparar servidor

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git python3 python3-pip nginx certbot python3-certbot-nginx ufw
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable
```

## 5) Criar usuario e pasta minimal

```bash
sudo useradd -r -m -d /opt/insidebot-license -s /usr/sbin/nologin insidebot || true
sudo mkdir -p /opt/insidebot-license
sudo chown -R insidebot:insidebot /opt/insidebot-license
```

## 6) Clonar via GitHub com sparse-checkout (somente arquivos de licenca)

Execute como usuario com permissao de git (ex.: root):

```bash
cd /opt/insidebot-license
sudo -u insidebot git init
sudo -u insidebot git remote add origin "$GH_REPO"
sudo -u insidebot git sparse-checkout init --no-cone
sudo -u insidebot git sparse-checkout set \
  tools/insidebot_license_server.py \
  tools/license_admin/index.html \
  tools/license_admin/styles.css \
  tools/license_admin/app.js \
  tools/deploy/minimal/insidebot-license.service \
  tools/deploy/minimal/nginx-insidebotcontrol.conf
sudo -u insidebot git fetch --depth=1 origin "$GH_BRANCH"
sudo -u insidebot git checkout "$GH_BRANCH"
```

## 7) Copiar arquivos para raiz de execucao

```bash
sudo cp /opt/insidebot-license/tools/insidebot_license_server.py /opt/insidebot-license/insidebot_license_server.py
sudo mkdir -p /opt/insidebot-license/license_data
sudo chown -R insidebot:insidebot /opt/insidebot-license
```

## 8) Configurar service (systemd)

```bash
sudo cp /opt/insidebot-license/tools/deploy/minimal/insidebot-license.service /etc/systemd/system/insidebot-license.service
```

Criar env do servico:

```bash
sudo bash -lc 'cat > /etc/insidebot-license.env <<EOF
INSIDEBOT_LICENSE_ADMIN_KEY=$ADMIN_KEY
INSIDEBOT_ADMIN_USERNAME=admin
INSIDEBOT_ADMIN_PASSWORD=F82615225b
INSIDEBOT_LICENSE_DB=/opt/insidebot-license/license_data/licenses.db
INSIDEBOT_LICENSE_HOST=127.0.0.1
INSIDEBOT_LICENSE_PORT=8090
INSIDEBOT_LICENSE_LOG_LEVEL=INFO
EOF'
sudo chmod 600 /etc/insidebot-license.env
```

Subir servico:

```bash
sudo systemctl daemon-reload
sudo systemctl enable insidebot-license.service
sudo systemctl restart insidebot-license.service
sudo systemctl status insidebot-license.service --no-pager
```

## 9) Configurar Nginx + SSL

```bash
sudo cp /opt/insidebot-license/tools/deploy/minimal/nginx-insidebotcontrol.conf /etc/nginx/sites-available/insidebotcontrol.conf
sudo sed -i "s/206.42.35.148/${ADMIN_ALLOWED_IP}/g" /etc/nginx/sites-available/insidebotcontrol.conf
sudo ln -sf /etc/nginx/sites-available/insidebotcontrol.conf /etc/nginx/sites-enabled/insidebotcontrol.conf
sudo nginx -t
sudo systemctl reload nginx
```

Certificado:

```bash
sudo certbot --nginx -d insidebotcontrol.com.br --non-interactive --agree-tos -m "$CERTBOT_EMAIL"
sudo certbot renew --dry-run
```

## 10) Teste de saude

```bash
curl -sS https://insidebotcontrol.com.br/api/health
```

Esperado: `{"ok": true, ...}`

## 10.1) Abrir painel web

No navegador:

```text
https://insidebotcontrol.com.br/admin
```

Credenciais de login padrao da tela:

- usuario: `admin`
- senha: `F82615225b`

Controle de acesso:

- `/admin` e `/api/v1/admin/*` liberados apenas para `ADMIN_ALLOWED_IP`.
- `/api/v1/license/validate` permanece publico para os EAs dos clientes.

## 11) Criar primeira licenca (API admin)

```bash
curl -sS -X POST "https://insidebotcontrol.com.br/api/v1/admin/license/upsert" \
  -H "Content-Type: application/json" \
  -H "X-Admin-Key: $ADMIN_KEY" \
  -d '{
    "token":"TOK_CLIENTE_001",
    "customer_name":"Cliente 1",
    "expires_at":"2026-12-31 23:59:59",
    "allowed_logins":["12345678"],
    "allowed_servers":["HantecMarkets-Server"],
    "active":true,
    "revoked":false
  }'
```

## 12) Atualizacao futura (GitHub -> VPS minimal)

```bash
cd /opt/insidebot-license
sudo -u insidebot git pull origin "$GH_BRANCH"
sudo cp /opt/insidebot-license/tools/insidebot_license_server.py /opt/insidebot-license/insidebot_license_server.py
sudo systemctl restart insidebot-license.service
sudo systemctl status insidebot-license.service --no-pager
```

## 13) Comandos de diagnostico

```bash
sudo journalctl -u insidebot-license.service -n 200 --no-pager
curl -sS https://insidebotcontrol.com.br/api/health
```

## 14) Checklist final

- [ ] DNS `insidebotcontrol.com.br` apontando para VPS.
- [ ] `insidebot-license.service` ativo e habilitado.
- [ ] `api/health` respondendo.
- [ ] HTTPS valido (certbot ok).
- [ ] Endpoint admin respondendo com `X-Admin-Key`.
- [ ] Primeira licenca criada com sucesso.
- [ ] Backup de `/opt/insidebot-license/license_data/licenses.db`.
