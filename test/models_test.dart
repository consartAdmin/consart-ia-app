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
    final u = ChatTurn.user('Quanto vendemos?');
    final r = ChatTurn.assistant(const AssistantAnswer(reply: 'R\$ 10 mil.'));
    expect(u.toHistory(), {'role': 'user', 'text': 'Quanto vendemos?'});
    expect(r.toHistory(), {'role': 'assistant', 'text': 'R\$ 10 mil.'});
  });

  test('lê o rascunho de e-mail', () {
    final a = AssistantAnswer.fromJson({
      'reply': 'Preparei o e-mail.',
      'action': {
        'type': 'email',
        'customer_id': '7',
        'customer_name': 'MERCADO SAO JOAO',
        'to': 'fin@x.com',
        'to_options': ['fin@x.com', 'loja@x.com'],
        'subject': 'Boleto em aberto',
        'body': 'Prezado cliente',
      },
    });
    expect(a.email, isNotNull);
    expect(a.email!.toRequestJson(), {
      'customer_id': '7',
      'to': 'fin@x.com',
      'subject': 'Boleto em aberto',
      'body': 'Prezado cliente',
    });
    final t = ChatTurn.assistant(a);
    expect(t.toHistory()['text'], contains('Rascunho de e-mail'));
    expect(AssistantAnswer.fromJson({'action': {'type': 'x'}}).email, isNull);
  });

  test('confirmação por voz', () {
    for (final s in ['pode enviar', 'Pode enviar!', 'manda', 'sim, pode enviar', 'envia', 'ok, manda', 'sim']) {
      expect(isSendConfirmation(s), isTrue, reason: s);
    }
    for (final s in ['quanto vendemos hoje', 'enviaram o boleto do joão?', 'não envia']) {
      expect(isSendConfirmation(s), isFalse, reason: s);
    }
    for (final s in ['cancela', 'não envia', 'nao manda ainda', 'esquece']) {
      expect(isSendCancel(s), isTrue, reason: s);
    }
    expect(isSendCancel('pode enviar'), isFalse);
  });
}
