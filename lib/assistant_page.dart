import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'api_service.dart';
import 'login_page.dart';
import 'models.dart';
import 'ui.dart';

/// Conversa por voz com a Consart. O celular transforma a fala em texto
/// (grátis), o ERP pergunta ao Claude consultando os módulos, e a resposta
/// volta falada pela voz do próprio celular (grátis). Depois de responder,
/// o microfone liga sozinho para a próxima pergunta (mãos livres).
class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

enum _Mode { idle, listening, thinking, speaking }

const _suggestions = [
  'Quanto vendemos hoje?',
  'O que vence para pagar essa semana?',
  'Qual o saldo do caixa?',
  'Quantas entregas faltam hoje?',
  'Quem está devendo para a gente?',
  'Tem estoque de cimento?',
  'Cobrar por e-mail um cliente com boleto vencido',
];

class _AssistantPageState extends State<AssistantPage> {
  final _api = ApiService.instance;
  final _speech = SpeechToText();
  final _tts = FlutterTts();
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatTurn> _turns = [];

  _Mode _mode = _Mode.idle;
  bool _speechReady = false;
  bool _ttsReady = false;

  /// Responder falando e ouvir de novo em seguida (mãos livres).
  bool _voiceOn = true;

  /// Quando a fala terminar, envia sozinho.
  bool _sendWhenDone = false;
  String _live = '';

  @override
  void dispose() {
    _speech.cancel();
    _tts.stop();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setMode(_Mode m) {
    if (mounted) setState(() => _mode = m);
  }

  // ── Voz da Consart (texto para fala) ────────────────────────────────
  Future<void> _initTts() async {
    if (_ttsReady) return;
    _ttsReady = true;
    try {
      await _tts.setLanguage('pt-BR');
      await _tts.setSpeechRate(0.5);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}
  }

  Future<void> _say(String text, {bool force = false}) async {
    if ((!_voiceOn && !force) || text.trim().isEmpty) return;
    await _initTts();
    _setMode(_Mode.speaking);
    try {
      await _tts.speak(text);
    } catch (_) {
    } finally {
      if (_mode == _Mode.speaking) _setMode(_Mode.idle);
    }
  }

  Future<void> _stopVoice() async {
    try {
      await _tts.stop();
    } catch (_) {}
    if (_mode == _Mode.speaking) _setMode(_Mode.idle);
  }

  // ── Microfone ────────────────────────────────────────────────────────
  Future<void> _onMicPressed() async {
    switch (_mode) {
      case _Mode.listening:
        // Parar: envia o que já foi falado.
        await _speech.stop();
        _setMode(_Mode.idle);
        if (_sendWhenDone && _text.text.trim().isNotEmpty) {
          _sendWhenDone = false;
          await _send();
        }
        _sendWhenDone = false;
      case _Mode.speaking:
        await _stopVoice();
      case _Mode.thinking:
        break;
      case _Mode.idle:
        await _startListening();
    }
  }

  Future<void> _startListening() async {
    await _stopVoice();
    if (!_speechReady) {
      _speechReady =
          await _speech.initialize(onStatus: _onStatus, onError: _onError);
      if (!mounted) return;
      if (!_speechReady) {
        showSnack(context,
            'Reconhecimento de voz indisponível. Libere o microfone nas configurações ou digite a pergunta.',
            error: true);
        return;
      }
    }
    final locale = await _ptBrLocale();
    if (!mounted) return;
    _sendWhenDone = true;
    _live = '';
    _text.clear();
    _setMode(_Mode.listening);
    await _speech.listen(
      onResult: _onResult,
      listenOptions: SpeechListenOptions(
        localeId: locale,
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 3),
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  Future<String?> _ptBrLocale() async {
    try {
      final locales = await _speech.locales();
      for (final l in locales) {
        if (l.localeId.toLowerCase().replaceAll('-', '_') == 'pt_br') {
          return l.localeId;
        }
      }
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith('pt')) return l.localeId;
      }
    } catch (_) {}
    return 'pt_BR';
  }

  void _onResult(SpeechRecognitionResult r) {
    final words = r.recognizedWords.trim();
    setState(() {
      _live = words;
      _text.text = words;
      _text.selection = TextSelection.collapsed(offset: words.length);
    });
    if (r.finalResult && _sendWhenDone && words.isNotEmpty) {
      _sendWhenDone = false;
      _send();
    }
  }

  void _onStatus(String status) {
    if (!mounted) return;
    if ((status == 'done' || status == 'notListening') &&
        _mode == _Mode.listening) {
      _setMode(_Mode.idle);
    }
  }

  void _onError(SpeechRecognitionError e) {
    if (!mounted) return;
    _sendWhenDone = false;
    if (_mode == _Mode.listening) _setMode(_Mode.idle);
    // Silêncio não é erro: só para de ouvir (encerra o modo mãos livres).
    if (e.errorMsg != 'error_no_match' &&
        e.errorMsg != 'error_speech_timeout') {
      showSnack(context, 'Erro no reconhecimento de voz (${e.errorMsg}).',
          error: true);
    }
  }

  // ── Conversa ─────────────────────────────────────────────────────────
  Future<void> _send([String? preset]) async {
    if (_mode == _Mode.thinking) return;
    if (_mode == _Mode.listening) {
      _sendWhenDone = false;
      await _speech.stop();
    }
    final text = (preset ?? _text.text).trim();
    if (text.isEmpty) {
      if (mounted) showSnack(context, 'Fale ou digite a pergunta.');
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();

    // E-mail esperando confirmação: "pode enviar" envia, "cancela" descarta.
    final pending = _pendingEmailTurn;
    if (pending != null && (isSendConfirmation(text) || isSendCancel(text))) {
      setState(() {
        _turns.add(ChatTurn.user(text));
        _text.clear();
        _live = '';
      });
      _scrollDown();
      if (isSendConfirmation(text)) {
        await _sendEmail(pending);
      } else {
        await _cancelEmail(pending);
      }
      return;
    }

    final history = [for (final t in _turns) t.toHistory()];
    setState(() {
      _turns.add(ChatTurn.user(text));
      _text.clear();
      _live = '';
      _mode = _Mode.thinking;
    });
    _scrollDown();

    AssistantAnswer? answer;
    try {
      answer = await _api.ask(text, history: history);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _turns.removeLast();
          _text.text = text;
        });
        showError(context, e);
        if (e.status == 401) await _logout();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _turns.removeLast();
          _text.text = text;
        });
        showError(context, e);
      }
    } finally {
      if (_mode == _Mode.thinking) _setMode(_Mode.idle);
    }
    if (answer == null || !mounted) return;
    final a = answer.reply.isEmpty
        ? AssistantAnswer(
            reply: 'Não encontrei uma resposta para isso.',
            highlights: answer.highlights,
            sources: answer.sources)
        : answer;
    setState(() => _turns.add(ChatTurn.assistant(a)));
    _scrollDown();
    await _say(a.reply);
    if (!mounted) return;
    // Mãos livres: depois de falar, já ouve a próxima pergunta.
    if (_voiceOn && _mode == _Mode.idle) await _startListening();
  }

  ChatTurn? get _pendingEmailTurn {
    for (final t in _turns.reversed) {
      if (!t.user && t.email != null) {
        return t.emailStatus == EmailStatus.pending ? t : null;
      }
    }
    return null;
  }

  Future<void> _sendEmail(ChatTurn turn) async {
    final draft = turn.email;
    if (draft == null || turn.emailStatus != EmailStatus.pending) return;
    await _stopVoice();
    setState(() => turn.emailStatus = EmailStatus.sending);
    try {
      await _api.sendEmail(draft);
      if (!mounted) return;
      setState(() => turn.emailStatus = EmailStatus.sent);
      final msg = 'Pronto, enviei o e-mail para ${draft.to}.';
      setState(() => _turns.add(
          ChatTurn.assistant(AssistantAnswer(reply: msg, sources: ['E-mail']))));
      _scrollDown();
      await _say(msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => turn.emailStatus = EmailStatus.pending);
      showError(context, e);
    }
  }

  Future<void> _cancelEmail(ChatTurn turn) async {
    if (turn.emailStatus != EmailStatus.pending) return;
    setState(() => turn.emailStatus = EmailStatus.cancelled);
    const msg = 'Tudo bem, não enviei o e-mail.';
    setState(() => _turns.add(
        ChatTurn.assistant(const AssistantAnswer(reply: msg))));
    _scrollDown();
    await _say(msg);
  }

  Future<void> _editEmail(ChatTurn turn) async {
    final draft = turn.email;
    if (draft == null) return;
    await _speech.cancel();
    await _stopVoice();
    if (!mounted) return;
    final edited = await showDialog<EmailDraft>(
      context: context,
      builder: (_) => _EmailEditDialog(draft: draft),
    );
    if (edited != null && mounted) setState(() => turn.email = edited);
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _newChat() async {
    await _speech.cancel();
    await _stopVoice();
    setState(() {
      _turns.clear();
      _text.clear();
      _live = '';
      _mode = _Mode.idle;
    });
  }

  Future<void> _logout() async {
    await _speech.cancel();
    await _stopVoice();
    await _api.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  String get _status => switch (_mode) {
        _Mode.listening => 'ouvindo…',
        _Mode.thinking => 'consultando o ERP…',
        _Mode.speaking => 'falando…',
        _Mode.idle => 'Assistente de IA · online',
      };

  // ── Tela ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF123A6B), Color(0xFF1E6FD9)],
            ),
          ),
        ),
        titleSpacing: 12,
        title: Row(children: [
          ConsartOrb(size: 40, glow: _mode != _Mode.idle),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Consart',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                Text(_status,
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: _voiceOn ? 'Desligar a voz' : 'Ligar a voz',
            icon: Icon(_voiceOn ? Icons.volume_up : Icons.volume_off),
            onPressed: () async {
              setState(() => _voiceOn = !_voiceOn);
              if (!_voiceOn) await _stopVoice();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'new' ? _newChat() : _logout(),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'new', child: Text('Nova conversa')),
              PopupMenuItem(
                value: 'logout',
                child: Text('Sair (${_api.userName ?? ''})'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: _mode == _Mode.listening
                ? _ListeningView(text: _live)
                : _turns.isEmpty
                    ? _EmptyView(
                        name: _api.userName, onAsk: (q) => _send(q))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        itemCount:
                            _turns.length + (_mode == _Mode.thinking ? 1 : 0),
                        itemBuilder: (_, i) => i == _turns.length
                            ? const _ThinkingBubble()
                            : _Bubble(
                                turn: _turns[i],
                                onReplay: (t) => _say(t, force: true),
                                onSendEmail: _sendEmail,
                                onCancelEmail: _cancelEmail,
                                onEditEmail: _editEmail,
                              ),
                      ),
          ),
          _InputBar(
            controller: _text,
            mode: _mode,
            onMic: _onMicPressed,
            onSend: () => _send(),
            theme: theme,
          ),
        ]),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final String? name;
  final ValueChanged<String> onAsk;
  const _EmptyView({required this.name, required this.onAsk});

  @override
  Widget build(BuildContext context) {
    final first = (name ?? '').trim().split(' ').first;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        const Center(child: ConsartOrb(size: 110, glow: true)),
        const SizedBox(height: 24),
        Text(
          first.isEmpty ? 'Olá!' : 'Olá, $first!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Toque no microfone e pergunte qualquer coisa sobre a empresa: '
          'vendas, estoque, clientes, financeiro, caixa, dívidas, entregas…',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _suggestions)
              ActionChip(label: Text(s), onPressed: () => onAsk(s)),
          ],
        ),
      ],
    );
  }
}

class _ListeningView extends StatelessWidget {
  final String text;
  const _ListeningView({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ConsartOrb(size: 150, glow: true),
          const SizedBox(height: 28),
          Text(
            text.isEmpty ? 'Pode falar…' : '"$text"',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ]),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Consultando…'),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatTurn turn;
  final ValueChanged<String> onReplay;
  final ValueChanged<ChatTurn> onSendEmail;
  final ValueChanged<ChatTurn> onCancelEmail;
  final ValueChanged<ChatTurn> onEditEmail;
  const _Bubble({
    required this.turn,
    required this.onReplay,
    required this.onSendEmail,
    required this.onCancelEmail,
    required this.onEditEmail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (turn.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 48, top: 4, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF1E6FD9),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(turn.text, style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    final a = turn.answer!;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(right: 36, top: 4, bottom: 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SelectableText(a.reply),
            ),
            if (a.highlights.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8, right: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(children: [
                  for (final h in a.highlights)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(
                            child: Text(h.label,
                                style: theme.textTheme.bodySmall)),
                        const SizedBox(width: 8),
                        Text(h.value,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ]),
                    ),
                ]),
              ),
            if (turn.email != null)
              _EmailCard(
                draft: turn.email!,
                status: turn.emailStatus,
                onSend: () => onSendEmail(turn),
                onCancel: () => onCancelEmail(turn),
                onEdit: () => onEditEmail(turn),
              ),
            Row(children: [
              if (a.sources.isNotEmpty)
                Expanded(
                  child: Text(
                    'Fontes: ${a.sources.join(' · ')}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.primary),
                  ),
                )
              else
                const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Ouvir de novo',
                iconSize: 18,
                icon: const Icon(Icons.volume_up_outlined),
                onPressed: () => onReplay(a.reply),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final _Mode mode;
  final VoidCallback onMic;
  final VoidCallback onSend;
  final ThemeData theme;
  const _InputBar({
    required this.controller,
    required this.mode,
    required this.onMic,
    required this.onSend,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final listening = mode == _Mode.listening;
    final busy = mode == _Mode.thinking;
    final color = listening ? const Color(0xFFE0393E) : const Color(0xFF1E6FD9);
    final hint = switch (mode) {
      _Mode.listening => 'Toque para parar e enviar',
      _Mode.speaking => 'Toque para interromper',
      _Mode.thinking => 'Consultando…',
      _Mode.idle => 'Toque e fale',
    };
    return Material(
      elevation: 6,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!listening)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: controller,
                enabled: !busy,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Ou digite a pergunta…',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: busy ? null : onSend,
                  ),
                ),
              ),
            ),
          GestureDetector(
            onTap: busy ? null : onMic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: busy ? Colors.grey : color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.18),
                    spreadRadius: listening ? 14 : 8,
                  ),
                ],
              ),
              child: Icon(
                listening
                    ? Icons.stop
                    : mode == _Mode.speaking
                        ? Icons.volume_off
                        : Icons.mic,
                color: Colors.white,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(hint, style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}

/// Rascunho do e-mail de cobrança, com Enviar / Editar / Cancelar.
class _EmailCard extends StatefulWidget {
  final EmailDraft draft;
  final EmailStatus status;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onEdit;
  const _EmailCard({
    required this.draft,
    required this.status,
    required this.onSend,
    required this.onCancel,
    required this.onEdit,
  });

  @override
  State<_EmailCard> createState() => _EmailCardState();
}

class _EmailCardState extends State<_EmailCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = widget.draft;
    final st = widget.status;
    return Container(
      margin: const EdgeInsets.only(top: 8, right: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
        color: scheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.mail_outline, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('E-mail de cobrança',
                  style: theme.textTheme.labelLarge),
            ),
            if (st == EmailStatus.sent)
              const Chip(
                  label: Text('Enviado'),
                  avatar: Icon(Icons.check, size: 16),
                  visualDensity: VisualDensity.compact),
            if (st == EmailStatus.cancelled)
              const Chip(
                  label: Text('Cancelado'),
                  visualDensity: VisualDensity.compact),
          ]),
          const SizedBox(height: 6),
          Text('Para: ${d.customerName.isEmpty ? '' : '${d.customerName} '}<${d.to}>',
              style: theme.textTheme.bodySmall),
          Text('Assunto: ${d.subject}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              d.body,
              maxLines: _expanded ? null : 4,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (st == EmailStatus.pending || st == EmailStatus.sending) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilledButton.icon(
                onPressed: st == EmailStatus.sending ? null : widget.onSend,
                icon: st == EmailStatus.sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send, size: 18),
                label: const Text('Enviar'),
              ),
              OutlinedButton(
                onPressed: st == EmailStatus.sending ? null : widget.onEdit,
                child: const Text('Editar'),
              ),
              TextButton(
                onPressed: st == EmailStatus.sending ? null : widget.onCancel,
                child: const Text('Cancelar'),
              ),
            ]),
            Text('Ou diga "pode enviar".', style: theme.textTheme.labelSmall),
          ],
        ],
      ),
    );
  }
}

class _EmailEditDialog extends StatefulWidget {
  final EmailDraft draft;
  const _EmailEditDialog({required this.draft});

  @override
  State<_EmailEditDialog> createState() => _EmailEditDialogState();
}

class _EmailEditDialogState extends State<_EmailEditDialog> {
  late String _to = widget.draft.to;
  late final _subject = TextEditingController(text: widget.draft.subject);
  late final _body = TextEditingController(text: widget.draft.body);

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = {
      ...widget.draft.toOptions,
      widget.draft.to,
    }.toList();
    return AlertDialog(
      title: const Text('Editar e-mail'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: _to,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Para'),
              items: [
                for (final o in options)
                  DropdownMenuItem(value: o, child: Text(o)),
              ],
              onChanged: (v) => setState(() => _to = v ?? _to),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subject,
              decoration: const InputDecoration(labelText: 'Assunto'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              minLines: 6,
              maxLines: 14,
              decoration: const InputDecoration(labelText: 'Mensagem'),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: () {
            if (_subject.text.trim().isEmpty || _body.text.trim().isEmpty) {
              return;
            }
            Navigator.pop(
              context,
              widget.draft.copyWith(
                to: _to,
                subject: _subject.text.trim(),
                body: _body.text.trim(),
              ),
            );
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
