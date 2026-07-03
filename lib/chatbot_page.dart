import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:jeevanlink/services/ai_services.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});

  @override
  _ChatbotPageState createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  Map<String, dynamic>? _userProfile;
  String _userRole = 'donor';
  
  // Store conversation history for context
  final List<Map<String, String>> _conversationHistory = [];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      if (mounted) {
        setState(() {
          _userProfile = data;
          _userRole = data['role'] ?? 'donor';
        });
        // Add welcome message after profile is loaded
        _addWelcomeMessage();
      }
    } catch (e) {
      print('Error loading profile: $e');
      // Add welcome message even if profile load fails
      if (mounted) {
        _addWelcomeMessage();
      }
    }
  }

  void _addWelcomeMessage() async {
    // Don't add welcome message if already exists
    if (_messages.isNotEmpty) return;
    
    setState(() => _isTyping = true);
    
    try {
      if (!AIService.isConfigured()) {
        setState(() {
          _isTyping = false;
          _messages.add(ChatMessage(
            text: '⚠️ AI Assistant is not configured. Please add your Gemini API key in services/ai_services.dart to enable intelligent conversations.',
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
        return;
      }

      final welcomePrompt = _userRole == 'hospital'
          ? 'Greet a hospital administrator who just opened the JeevanLink blood donation app. Welcome them warmly and briefly explain how you can help them manage blood requests, coordinate with donors, and handle emergencies. Keep it friendly and concise (2-3 sentences).'
          : 'Greet a blood donor who just opened the JeevanLink blood donation app. Welcome them warmly and briefly explain how you can help them with donation questions, eligibility, and emergency support. Keep it friendly and concise (2-3 sentences).';

      final response = await AIService.sendMessage(
        userMessage: welcomePrompt,
        userRole: _userRole,
        conversationHistory: [],
      );

      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(ChatMessage(
            text: response,
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(ChatMessage(
            text: 'Hello! I\'m your AI assistant for JeevanLink. I\'m here to help with blood donation questions. How can I assist you today?',
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
      }
    }
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      
      // Add to conversation history
      _conversationHistory.add({'role': 'user', 'content': text});
    });

    _messageController.clear();
    _scrollToBottom();

    // Generate AI response
    _generateAIResponse(text);
  }

  Future<void> _generateAIResponse(String userMessage) async {
    setState(() => _isTyping = true);
    _scrollToBottom();

    try {
      if (!AIService.isConfigured()) {
        setState(() {
          _isTyping = false;
          _messages.add(ChatMessage(
            text: '⚠️ I cannot respond right now. The AI service needs to be configured with a Gemini API key.',
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
        return;
      }

      // Call Gemini API
      final response = await AIService.sendMessage(
        userMessage: userMessage,
        userRole: _userRole,
        conversationHistory: _conversationHistory,
      );

      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(ChatMessage(
            text: response,
            isUser: false,
            timestamp: DateTime.now(),
          ));
          
          // Add to conversation history
          _conversationHistory.add({'role': 'assistant', 'content': response});
          
          // Keep only last 12 messages (6 exchanges) to manage token usage
          if (_conversationHistory.length > 12) {
            _conversationHistory.removeRange(0, _conversationHistory.length - 12);
          }
        });

        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(ChatMessage(
            text: 'I apologize, I\'m having trouble connecting right now. Please check your internet connection and try again.',
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
      }
      print('Error generating AI response: $e');
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _conversationHistory.clear();
      _addWelcomeMessage();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.smart_toy,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Assistant',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Powered by Llama 3.1',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _clearChat,
            tooltip: 'Clear chat',
          ),
        ],
      ),
      body: Column(
        children: [
          // AI Status Indicator
          if (!AIService.isConfigured())
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.orange.shade100,
              child: Text(
                '⚠️ AI not configured. Add Gemini API key to enable.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.orange.shade900,
                ),
              ),
            ),
          
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.red.shade50,
                    Colors.white,
                  ],
                ),
              ),
              child: _messages.isEmpty && !_isTyping
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Start a conversation',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_isTyping ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length && _isTyping) {
                          return _buildTypingIndicator();
                        }

                        final message = _messages[index];
                        return _buildMessageBubble(message);
                      },
                    ),
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Icon(
              Icons.smart_toy,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Text(
                  'AI is thinking',
                  style: GoogleFonts.poppins(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                const SpinKitThreeBounce(
                  color: Colors.grey,
                  size: 16,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: const Icon(
                Icons.smart_toy,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: message.isUser ? Colors.red : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: message.isUser ? null : Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: message.isUser 
                        ? Colors.red.withOpacity(0.3)
                        : Colors.grey.shade200,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.text,
                style: GoogleFonts.poppins(
                  color: message.isUser ? Colors.white : Colors.black87,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.red,
              child: Text(
                _userProfile?['full_name']?.substring(0, 1).toUpperCase() ?? 'U',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Ask me anything about blood donation...',
                hintStyle: GoogleFonts.poppins(color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: GoogleFonts.poppins(),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: _sendMessage,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: IconButton(
              onPressed: () => _sendMessage(_messageController.text),
              icon: const Icon(Icons.send, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}