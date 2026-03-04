# InsideBot - Seguranca para Comercializacao

## O que esta implementado no InsideBot.mq5
- Distribuicao somente em `.ex5` (sem codigo-fonte no cliente).
- Validacao de licenca no `OnInit` e revalidacao periodica em runtime.
- Revogacao imediata (`revoked=true`) com bloqueio de execucao.
- Janela de graca offline controlada por `LicenseGracePeriodHours`.
- Restricao de conta: apenas `ACCOUNT_TRADE_MODE_REAL` + `ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`.
- Watermark em tela: `InsideBot - Acesso(<cliente>)`.
- Logs estrategicos silenciados por padrao.
- JSON de operacoes sanitizado e salvamento silencioso.
- URL de validacao default no release atual: `https://insidebotcontrol.com.br`.

## Parametros de seguranca (build/release)

No `InsideBot`, os parametros abaixo ficam ocultos no painel e devem ser definidos no build:

- `EnableLicenseValidation`
- `LicenseServerBaseUrl`
- `LicenseToken`
- `LicensedCustomerName`
- `LicenseCheckIntervalMinutes`
- `LicenseGracePeriodHours`
- `EnforceLiveHedgeAccount`

Script de apoio para aplicar token/cliente antes da compilacao:
- `tools/aplicar_release_insidebot.ps1`

## Contrato do endpoint de licenca

URL:
- `POST {LicenseServerBaseUrl}/api/v1/license/validate`
- Se `LicenseServerBaseUrl` ja vier com `/api/...`, o bot usa direto.

Request JSON:
```json
{
  "token": "...",
  "login": "12345678",
  "server": "Broker-Real",
  "company": "Broker Name",
  "name": "Nome da Conta",
  "program": "InsideBot",
  "build": "xxxxx"
}
```

Response JSON esperado:
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

## Servidor e operacao

Arquivos:
- `tools/insidebot_license_server.py`
- `tools/iniciar_insidebot_license_server.ps1`
- `tools/gerenciar_insidebot_licencas.ps1`

Guia completo:
- `docs/InsideBot_LICENSE_SERVER_SETUP.md`

## Grace Period (item critico)
`Grace Period` e uma janela offline (ex.: 24h) apos a ultima validacao online com sucesso.
- Se o servidor cair temporariamente, o bot segue operando dentro da janela.
- Se passar da janela sem nova validacao online, bloqueia novas execucoes.
- Se a licenca estiver revogada/expirada, nao usa grace.

## Item 21: mover logica critica para servidor
Modelo com protecao maxima:
- EA local como executor + risk guard.
- Sinais e decisao de estrategia no servidor.
- Cliente recebe apenas instrucao operacional.

Impacto:
- Maior protecao contra engenharia reversa.
- Exige infraestrutura 24/7 de baixa latencia e redundancia.
- Aumenta custo e complexidade operacional.

## Hardening recomendado no backend
- HTTPS com certificado valido.
- Chave admin forte e secreta.
- Rate limit por IP/conta.
- Auditoria de requests e alertas de abuso.
- Lista de revogacao imediata.
- Backup diario do banco de licencas.

## Pipeline de release
- Build comercial separado do `prime_bot`.
- Versionamento por cliente/lote.
- Hash do binario e registro de entrega.
- Controle de acesso ao repositorio e 2FA.
- Changelog por release.
