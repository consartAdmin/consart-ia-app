import 'package:consart_ia/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lê a resposta da assistente', () {
    final a = AssistantAnswer.fromJson({
      'reply': ' Hoje foram 23 vendas. ',
      'highlights': [
        {'label': 'Vendas hoje', 'value': 'R\$ 18.430,00'},
        {'label': '', 'value': 'ignorado'},
        'lixo',
      ],
      'sources': ['Vendas', ' ', 'Financeiro'],
    });
    expect(a.reply, 'Hoje foram 23 vendas.');
    expect(a.highlights.length, 1);
    expect(a.highlights.first.value, 'R\$ 18.430,00');
    expect(a.sources, ['Vendas', 'Financeiro']);
  });

  test('resposta vazia não quebra', () {
    final a = AssistantAnswer.fromJson({});
    expect(a.reply, '');
    expect(a.highlights, isEmpty);
    expect(a.sources, isEmpty);
  });

  test('histórico da conversa', () {
    final u = const ChatTurn.user('Quanto vendemos?');
    final r = ChatTurn.assistant(const AssistantAnswer(reply: 'R\$ 10 mil.'));
    expect(u.toHistory(), {'role': 'user', 'text': 'Quanto vendemos?'});
    expect(r.toHistory(), {'role': 'assistant', 'text': 'R\$ 10 mil.'});
  });
}
