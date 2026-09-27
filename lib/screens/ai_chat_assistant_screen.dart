import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/food_item.dart';
import '../services/app_session.dart';
import '../widgets/live_results_panel.dart';

class AiChatAssistantScreen extends StatefulWidget {
  final VoidCallback onBack;
  final Function(String route)? onNavigate;

  const AiChatAssistantScreen({
    super.key,
    required this.onBack,
    this.onNavigate,
  });

  @override
  State<AiChatAssistantScreen> createState() => _AiChatAssistantScreenState();
}

class _AiChatAssistantScreenState extends State<AiChatAssistantScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;

  /// True when the last answer came from the backend LLM proxy.
  bool _lastAnswerFromBackend = false;

  late List<ChatMessage> _messages;

  @override
  void initState() {
    super.initState();
    _messages = [
      ChatMessage(
        id: '1',
        text:
            'I want to package dried mango with 5 months shelf life. Suggest the best packaging.',
        isUser: true,
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      ChatMessage(
        id: '2',
        text: 'For dried mango slices, I recommend the following barrier structure to prevent browning and moisture uptake:',
        isUser: false,
        timestamp: DateTime.now().subtract(const Duration(minutes: 4)),
        hasRecommendationCard: true,
        cardTitle: 'Recommended Multi-Layer Pouch for Dried Mango',
        bulletPoints: [
          'Material: PET 12µ + MET PET 12µ + LDPE 75µ',
          'Shelf Life: 8-10 months (Exceeds 5 months target)',
          'OTR (Oxygen Transmission): < 1 cc/m²/day',
          'WVTR (Moisture Barrier): < 0.5 g/m²/day',
          'Cost: ~₹2.10 per pack',
          'Certifications: US-FDA 21 CFR & EU 10/2011 Food Contact',
        ],
        cardImageUrl:
            'https://images.unsplash.com/photo-1601493700631-2b16ec4b4716?w=600&auto=format&fit=crop&q=80',
      ),
    ];
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage([String? presetText]) {
    final text = presetText ?? _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: text,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );
      _textController.clear();
      _isTyping = true;
    });

    _scrollToBottom();

    _fetchAssistantReply(text);
  }

  /// Asks the backend, which injects live product + simulation context into the
  /// system prompt. Falls back to the local curated answer when offline.
  Future<void> _fetchAssistantReply(String text) async {
    try {
      final reply = await AppSession.instance.api.sendChatMessage(
        sessionId: AppSession.instance.chatSessionId,
        message: text,
        productId: AppSession.instance.productId,
        simId: AppSession.instance.simId,
      );
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _lastAnswerFromBackend = reply['used_llm'] == true;
        _messages.add(
          ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: '${reply['content']}',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
      return;
    } catch (_) {
      // Offline — fall through to the curated local answer.
    }
    if (!mounted) return;
    setState(() => _lastAnswerFromBackend = false);
    _fallbackReply(text);
  }

  void _fallbackReply(String text) {
      ChatMessage response;
      if (text.toLowerCase().contains('chips') ||
          text.toLowerCase().contains('potato')) {
        response = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: 'Here is the optimal AI specification for potato chips with high crunch preservation:',
          isUser: false,
          timestamp: DateTime.now(),
          hasRecommendationCard: true,
          cardTitle: 'Potato Chips High-Barrier Foil Bag',
          bulletPoints: [
            'Structure: BOPP 20µ + Met-BOPP 18µ + PE 35µ',
            'Gas Flush: 99.5% Nitrogen (MAP) to prevent rancidity',
            'OTR: < 0.8 cc/m²/day | WVTR: < 0.4 g/m²/day',
            'Predicted Shelf Life: 6 Months guaranteed',
            'Unit Cost: ₹1.45 @ 50,000 batch volume',
          ],
          cardImageUrl:
              'https://images.unsplash.com/photo-1566478989037-eec170784d0b?w=600&auto=format&fit=crop&q=80',
        );
      } else if (text.toLowerCase().contains('bio') ||
          text.toLowerCase().contains('eco')) {
        response = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: 'For 100% biodegradable and compostable eco-packaging, here is the verified formulation:',
          isUser: false,
          timestamp: DateTime.now(),
          hasRecommendationCard: true,
          cardTitle: 'Certified Compostable Bio-Laminate',
          bulletPoints: [
            'Layers: NatureFlex™ Cellulose + PBS / Bio-PBS + PLA Sealant',
            'Standards: EN 13432 & ASTM D6400 (Home & Industrial Compost)',
            'Shelf Life: 4-6 Months under dry storage (<25°C, <60% RH)',
            'Carbon Footprint: -65% compared to fossil plastics',
          ],
          cardImageUrl:
              'https://images.unsplash.com/photo-1542838132-92c53300491e?w=600&auto=format&fit=crop&q=80',
        );
      } else {
        response = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text:
              'Based on biochemical stability models (water activity aw, lipid oxidation, and microbial growth kinetics), I have calculated the optimal barrier thickness for "$text".\n\nWould you like me to generate a 3D digital prototype or compare pricing across certified suppliers in your region?',
          isUser: false,
          timestamp: DateTime.now(),
        );
      }

      setState(() {
        _isTyping = false;
        _messages.add(response);
      });

      _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: const Column(
          children: [
            Text(
              'PackIT AI Assistant',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            Text(
              'Your Personal AI Packaging Expert',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF10B981)),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: LiveBadge(
                isLive: _lastAnswerFromBackend,
                loading: _isTyping,
                liveLabel: 'LLM',
                offlineLabel: 'offline',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: () {
              setState(() => _messages.clear());
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Chat history cleared')),
              );
            },
          ),
        ],
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Quick Suggestion Chips
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildPromptChip('🥭 Dried mango 5 mo shelf life'),
                  _buildPromptChip('🥔 Potato chips nitrogen flush'),
                  _buildPromptChip('🌿 100% Compostable eco packaging'),
                  _buildPromptChip('🥛 Pasteurized milk aseptic carton'),
                ],
              ),
            ),

            const Divider(height: 1),

            // Chat Messages List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildMessageBubble(msg, isDark);
                },
              ),
            ),

            if (_isTyping)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF4F46E5),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'PackIT AI is thinking...',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Bottom Message Input Field
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceDark : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? AppTheme.cardBorderDark
                        : AppTheme.cardBorderLight,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'Ask anything about food packaging...',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF1F5F9),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                      onPressed: () => _sendMessage(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptChip(String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label),
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        backgroundColor: const Color(0xFFEEF2FF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFC7D2FE)),
        ),
        onPressed: () => _sendMessage(label),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isDark) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
            ),
          ),
          child: Text(
            msg.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    } else {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14, right: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF10B981), Color(0xFF4F46E5)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.eco_rounded,
                        color: Colors.white, size: 14),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'PackIT AI',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      msg.text,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        height: 1.35,
                      ),
                    ),
                    if (msg.hasRecommendationCard &&
                        msg.bulletPoints != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color:
                                const Color(0xFF4F46E5).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (msg.cardTitle != null) ...[
                              Text(
                                msg.cardTitle!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF4F46E5),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            ...msg.bulletPoints!.map((b) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('• ',
                                          style: TextStyle(
                                              color: Color(0xFF10B981),
                                              fontWeight: FontWeight.bold)),
                                      Expanded(
                                        child: Text(
                                          b,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w500,
                                            color: isDark
                                                ? Colors.white70
                                                : const Color(0xFF334155),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                            if (msg.cardImageUrl != null) ...[
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  msg.cardImageUrl!,
                                  height: 110,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}
