/// Um número ou fato mostrado na tela junto com a resposta.
class Highlight {
  final String label;
  final String value;
  const Highlight(this.label, this.value);
}

/// E-mail de cobrança preparado pela Consart. Só é enviado quando o
/// usuário confirma (botão Enviar ou falando "pode enviar").
class EmailDraft {
  final String customerId;
  final String customerName;
  final String to;
  final List<String> toOptions;
  final String subject;
  final String body;

  const EmailDraft({
    required this.customerId,
    required this.customerName,
    required this.to,
    this.toOptions = const [],
    required this.subject,
    required this.body,
  });

  static EmailDraft? fromJson(dynamic json) {
    if (json is! Map || json['type'] != 'email') return null;
    final to = (json['to'] ?? '').toString().trim();
    final id = (json['customer_id'] ?? '').toString().trim();
    if (to.isEmpty || id.isEmpty) return null;
    final opts = json['to_options'];
    return EmailDraft(
      customerId: id,
      customerName: (json['customer_name'] ?? '').toString(),
      to: to,
      toOptions: [
        if (opts is List)
          for (final o in opts)
            if (o.toString().trim().isNotEmpty) o.toString().trim(),
      ],
      subject: (json['subject'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
    );
  }

  EmailDraft copyWith({String? to, String? subject, String? body}) => EmailDraft(
        customerId: customerId,
        customerName: customerName,
        to: to ?? this.to,
        toOptions: toOptions,
        subject: subject ?? this.subject,
        body: body ?? this.body,
      );

  Map<String, String> toRequestJson() => {
        'customer_id': customerId,
        'to': to,
        'subject': subject,
        'body': body,
      };

  /// Resumo que volta no histórico, para a Consart poder ajustar o rascunho.
  String get historyNote =>
      '[Rascunho de e-mail para $customerName <$to>. Assunto: $subject. Mensagem: $body]';
}

/// Estado do e-mail mostrado na conversa.
enum EmailStatus { pending, sending, sent, cancelled }

/// Resposta da Consart: o que ela fala, os destaques e os módulos consultados.
class AssistantAnswer {
  final String reply;
  final List<Highlight> highlights;
  final List<String> sources;
  final EmailDraft? email;

  const AssistantAnswer({
    required this.reply,
    this.highlights = const [],
    this.sources = const [],
    this.email,
  });

  factory AssistantAnswer.fromJson(Map<String, dynamic> json) {
    final hl = json['highlights'];
    final src = json['sources'];
    return AssistantAnswer(
      reply: (json['reply'] ?? '').toString().trim(),
      highlights: [
        if (hl is List)
          for (final h in hl.whereType<Map>())
            if ((h['label'] ?? '').toString().isNotEmpty)
              Highlight(h['label'].toString(), (h['value'] ?? '').toString()),
      ],
      sources: [
        if (src is List)
          for (final s in src)
            if (s.toString().trim().isNotEmpty) s.toString().trim(),
      ],
      email: EmailDraft.fromJson(json['action']),
    );
  }
}

/// "pode enviar", "manda", "envia sim"… confirma o e-mail pendente.
bool isSendConfirmation(String text) {
  final t = text.toLowerCase().trim();
  return RegExp(r'^(sim[, ]*)?(pode |podes |ok[, ]*)?(enviar|envia|envie|mandar|manda|mande|disparar|dispara)\b')
          .hasMatch(t) ||
      RegExp(r'^(sim|ok|isso)[,.! ]*(pode )?(enviar|mandar)?[.! ]*$').hasMatch(t);
}

/// "cancela", "não envia"… descarta o e-mail pendente.
bool isSendCancel(String text) {
  final t = text.toLowerCase().trim();
  return RegExp(r'^(não|nao)[, ]*(envia|enviar|manda|mandar)\b').hasMatch(t) ||
      RegExp(r'^(cancela|cancelar|cancele|esquece|deixa)\b').hasMatch(t);
}

/// Uma fala da conversa (do usuário ou da Consart).
class ChatTurn {
  final bool user;
  final String text;
  final AssistantAnswer? answer;

  /// E-mail desta resposta (pode ser editado antes de enviar).
  EmailDraft? email;
  EmailStatus emailStatus = EmailStatus.pending;

  ChatTurn.user(this.text)
      : user = true,
        answer = null;
  ChatTurn.assistant(AssistantAnswer this.answer)
      : user = false,
        text = answer.reply,
        email = answer.email;

  Map<String, String> toHistory() {
    var t = text;
    if (email != null) {
      t += '\n${email!.historyNote}';
      if (emailStatus == EmailStatus.sent) t += '\n[E-mail enviado.]';
      if (emailStatus == EmailStatus.cancelled) t += '\n[E-mail cancelado.]';
    }
    return {'role': user ? 'user' : 'assistant', 'text': t};
  }
}
