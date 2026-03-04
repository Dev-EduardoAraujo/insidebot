# InsideBot - Checklist de Deploy em VPS via GitHub

Checklist operacional para publicar o servidor de licencas do `InsideBot` em `insidebotcontrol.com.br`.

## 0. Pre-requisitos

- [ ] Dominio `insidebotcontrol.com.br` com registro DNS gerenciavel.
- [ ] VPS Linux (Ubuntu 22.04+ recomendado) com acesso `sudo`.
- [ ] Repositorio no GitHub (publico ou privado).
- [ ] Porta 80/443 liberadas no provedor.

## 1. DNS

- [ ] Criar/validar registro `A` para `insidebotcontrol.com.br` apontando para o IP da VPS.
- [ ] Aguardar propagacao e testar:

```bash
nslookup insidebotcontrol.com.br
```

## 2. Bootstrap da VPS

- [ ] Atualizar sistema:

```bash
sudo apt update && sudo apt upgrade -y
```

- [ ] Instalar dependencias:

```bash
sudo apt install -y git python3 python3-pip python3-venv nginx certbot python3-certbot-nginx ufw
```

- [ ] (Opcional) Criar usuario de deploy:

```bash
sudo adduser deploy
sudo usermod -aG sudo deploy
```

## 3. Firewall

- [ ] Ativar regras minimas:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable
sudo ufw status
```

## 4. Subir codigo via GitHub

Escolha **uma** forma de acesso ao GitHub:

### 4.1 Opcao A: HTTPS + token (rapida)

- [ ] Clonar repo:

```bash
sudo mkdir -p /opt
cd /opt
sudo git clone https://github.com/SEU_USUARIO/SEU_REPO.git bot_MT5
sudo chown -R $USER:$USER /opt/bot_MT5
```

### 4.2 Opcao B: SSH deploy key (recomendado)

- [ ] Gerar chave na VPS:

```bash
ssh-keygen -t ed25519 -C "insidebot-vps" -f ~/.ssh/insidebot_vps -N ""
cat ~/.ssh/insidebot_vps.pub
```

- [ ] Adicionar a chave publica como Deploy Key no GitHub (repo).
- [ ] Criar `~/.ssh/config`:

```bash
cat > ~/.ssh/config << 'EOF'
Host github-insidebot
  HostName github.com
  User git
  IdentityFile ~/.ssh/insidebot_vps
  IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config
```

- [ ] Clonar:

```bash
sudo mkdir -p /opt
cd /opt
git clone git@github-insidebot:SEU_USUARIO/SEU_REPO.git bot_MT5
```

## 5. Preparar servidor de licenca

- [ ] Entrar no projeto:

```bash
cd /opt/bot_MT5
```

- [ ] Criar pasta de dados:

```bash
mkdir -p tools/license_data
```

- [ ] Gerar chave admin forte:

```bash
openssl rand -hex 32
```

- [ ] Editar unit file com sua chave:

```bash
sudo cp tools/deploy/insidebot-license.service /etc/systemd/system/insidebot-license.service
sudo nano /etc/systemd/system/insidebot-license.service
```

Ajustar no arquivo:
- `WorkingDirectory=/opt/bot_MT5`
- `ExecStart=/usr/bin/python3 /opt/bot_MT5/tools/insidebot_license_server.py`
- `INSIDEBOT_LICENSE_ADMIN_KEY=<SUA_CHAVE>`

- [ ] Subir servico:

```bash
sudo systemctl daemon-reload
sudo systemctl enable insidebot-license.service
sudo systemctl start insidebot-license.service
sudo systemctl status insidebot-license.service --no-pager
```

## 6. Nginx + HTTPS

- [ ] Instalar configuracao nginx:

```bash
sudo cp tools/deploy/nginx-insidebotcontrol.conf /etc/nginx/sites-available/insidebotcontrol.conf
sudo ln -sf /etc/nginx/sites-available/insidebotcontrol.conf /etc/nginx/sites-enabled/insidebotcontrol.conf
sudo nginx -t
sudo systemctl reload nginx
```

- [ ] Emitir certificado:

```bash
sudo certbot --nginx -d insidebotcontrol.com.br --non-interactive --agree-tos -m SEU_EMAIL@DOMINIO.COM
```

- [ ] Verificar renovacao:

```bash
sudo systemctl status certbot.timer --no-pager
sudo certbot renew --dry-run
```

## 7. Smoke test (producao)

- [ ] Health check:

```bash
curl -sS https://insidebotcontrol.com.br/api/health
```

- [ ] Criar primeira licenca (admin):

```bash
curl -sS -X POST "https://insidebotcontrol.com.br/api/v1/admin/license/upsert" \
  -H "Content-Type: application/json" \
  -H "X-Admin-Key: SUA_CHAVE_ADMIN" \
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

- [ ] Validar endpoint do EA:

```bash
curl -sS -X POST "https://insidebotcontrol.com.br/api/v1/license/validate" \
  -H "Content-Type: application/json" \
  -d '{
    "token":"TOK_CLIENTE_001",
    "login":"12345678",
    "server":"HantecMarkets-Server",
    "company":"Hantec",
    "name":"Conta Cliente",
    "program":"InsideBot",
    "build":"4750"
  }'
```

## 8. Processo de release para cliente

- [ ] No seu ambiente local, aplicar token/cliente no EA:

```powershell
powershell -ExecutionPolicy Bypass -File tools\aplicar_release_insidebot.ps1 `
  -Token "TOK_CLIENTE_001" `
  -Cliente "Cliente 1" `
  -LicenseUrl "https://insidebotcontrol.com.br"
```

- [ ] Compilar `sliced/InsideBot.mq5`.
- [ ] Entregar apenas `.ex5`.
- [ ] Cliente deve liberar WebRequest para `https://insidebotcontrol.com.br` no MT5.

## 9. Atualizacao via GitHub (rotina)

- [ ] Atualizar codigo:

```bash
cd /opt/bot_MT5
git pull
```

- [ ] Reiniciar servico:

```bash
sudo systemctl restart insidebot-license.service
sudo systemctl status insidebot-license.service --no-pager
```

- [ ] Testar health:

```bash
curl -sS https://insidebotcontrol.com.br/api/health
```

## 10. Backup e observabilidade

- [ ] Backup diario do banco:

```bash
mkdir -p /opt/backups/insidebot
cp /opt/bot_MT5/tools/license_data/licenses.db /opt/backups/insidebot/licenses_$(date +%F_%H%M%S).db
```

- [ ] Logs do servico:

```bash
sudo journalctl -u insidebot-license.service -n 200 --no-pager
```

## 11. Checklist final (go-live)

- [ ] DNS resolvendo para IP correto.
- [ ] HTTPS valido no dominio.
- [ ] `insidebot-license.service` ativo e habilitado.
- [ ] `api/health` respondendo `ok=true`.
- [ ] Criacao/validacao de licenca funcionando.
- [ ] Chave admin forte e secreta.
- [ ] Backup do SQLite em rotina.
- [ ] `InsideBot` compilado e entregue em `.ex5`.

