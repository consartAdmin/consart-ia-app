/// Um número ou fato mostrado na tela junto com a resposta.
class Highlight {
  final String label;
  final String value;
  const Highlight(this.label, this.value);
}

/// Resposta da Consart: o que ela fala, os destaques e os módulos consultados.
class AssistantAnswer {
  final String reply;
  final List<Highlight> highlights;
  final List<String> sources;

  const AssistantAnswer({
    required this.reply,
    this.highlights = const [],
    this.sources = const [],
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
    );
  }
}

/// Uma fala da conversa (do usuário ou da Consart).
class ChatTurn {
  final bool user;
  final String text;
  final AssistantAnswer? answer;
  const ChatTurn.user(this.text)
      : user = true,
        answer = null;
  ChatTurn.assistant(AssistantAnswer this.answer)
      : user = false,
        text = answer.reply;

  Map<String, String> toHistory() =>
      {'role': user ? 'user' : 'assistant', 'text': text};
}
