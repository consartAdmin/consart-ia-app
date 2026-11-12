# Consart

Assistente de IA por voz do ERP Infinity (Android e iOS, Flutter).

Você toca no microfone e pergunta qualquer coisa sobre a empresa: vendas,
produtos e estoque, clientes, orçamentos, pedidos, contas a pagar e a
receber, caixa, dívidas, entregas e notas de entrada. A Consart responde
falando e mostra os números na tela. Depois de responder, ela já ouve a
próxima pergunta (mãos livres).

- **Voz:** o reconhecimento de fala e a voz da resposta são do próprio
  celular (`speech_to_text` e `flutter_tts`), sem custo.
- **Inteligência:** o app envia a pergunta para `POST /api/assistant/chat`
  no ERP. O ERP usa o Claude (chave `ANTHROPIC_API_KEY` no Cloud Run) e
  consulta os módulos pelas rotas GET do próprio ERP, com o login do
  usuário. Só consulta: não cria, altera ou exclui nada.
- **E-mail de cobrança:** peça "cobra o cliente X do boleto vencido". A Consart
  prepara o e-mail (só para e-mails do cadastro do cliente) e ele só é enviado
  depois que você toca em **Enviar** ou diz "pode enviar". O envio usa a conta
  de e-mail do ERP (`POST /api/assistant/send-email`).
- **Limite:** `ASSISTANT_DAILY_LIMIT` perguntas por usuário por dia (padrão 150).

## Build

Cada push na `main` gera o APK em
`releases/latest/download/consart-ia.apk` (GitHub Actions). O workflow do
iOS envia para o TestFlight quando os segredos da Apple estiverem
configurados.

Android: `br.com.consart.consart_ia` · iOS: `br.com.consart.ia`
