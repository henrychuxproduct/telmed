import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:google_generative_ai/google_generative_ai.dart'; 

// --- ENHANCED MESSAGE DATA MODEL ---
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? attachedFileName;
  final String? attachedFileExtension;
  final int? attachedFileSize;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.attachedFileName,
    this.attachedFileExtension,
    this.attachedFileSize,
  });

  bool get hasAttachment => attachedFileName != null;
}

class TelmedAiChatPage extends StatefulWidget {
  const TelmedAiChatPage({super.key});

  @override
  State<TelmedAiChatPage> createState() => _TelmedAiChatPageState();
}

class _TelmedAiChatPageState extends State<TelmedAiChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // File Picking State
  PlatformFile? _selectedFile;

  // Initial welcome message (UI only)
  final List<ChatMessage> _messages = [
    ChatMessage(
      text: "Hello! I am your Telmed Assistant. I can review your lab results, check medical documents, or answer general health questions. How can I help you today?",
      isUser: false,
      timestamp: DateTime.now(),
    )
  ];

  bool _isTyping = false;

  // --- GEMINI AI STATE ---
  // Provide at build time (do NOT hard-code keys in source):
  //   flutter run -d chrome --dart-define=GEMINI_API_KEY=xxxx
  // NOTE: on Flutter web any key in the bundle is readable by visitors, so
  // for production route requests through your backend (e.g. the Vercel API)
  // or Firebase AI Logic instead.
  static const String _geminiKey = String.fromEnvironment('GEMINI_API_KEY');
  // gemini-1.5-flash has been shut down by Google. Check
  // https://ai.google.dev/gemini-api/docs/models for the current model name.
  static const String _geminiModel =
      String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-2.5-flash');

  late final GenerativeModel _model;
  late final ChatSession _chatSession;

  @override
  void initState() {
    super.initState();
    _initializeGemini();
  }

  void _initializeGemini() {
    // Initializes the Flash model (key + model come from --dart-define)
    _model = GenerativeModel(
      model: _geminiModel,
      apiKey: _geminiKey,
      systemInstruction: Content.system(
        'You are the Telmed Assistant, a secure and professional virtual healthcare assistant. '
        'You help patients understand lab results, review uploaded medical documents, and answer health queries. '
        'Always maintain a compassionate tone and remind users to consult a certified human doctor for formal diagnoses.'
      ),
    );
    
    // startChat maintains the conversation history automatically
    _chatSession = _model.startChat();
  }

  // --- FILE PICKER LOGIC ---
  Future<void> _pickDocument() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'png', 'jpg', 'jpeg'],
        withData: true, 
      );

      if (result != null) {
        setState(() {
          _selectedFile = result.files.first;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to pick document. Please try again.")),
      );
    }
  }

  void _clearSelectedFile() {
    setState(() {
      _selectedFile = null;
    });
  }

  // Helper to resolve MIME types for the Gemini API
  String _resolveMimeType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'pdf': return 'application/pdf';
      case 'png': return 'image/png';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'txt': return 'text/plain';
      default: return 'application/octet-stream';
    }
  }

  // --- SEND LOGIC ---
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final currentFile = _selectedFile; 
    
    if (text.isEmpty && currentFile == null) return;

    // 1. Update UI immediately
    setState(() {
      _messages.insert(0, ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
        attachedFileName: currentFile?.name,
        attachedFileExtension: currentFile?.extension,
        attachedFileSize: currentFile?.size,
      ));

      _isTyping = true;
      _selectedFile = null; 
    });

    _messageController.clear();
    _scrollToBottom();

    // 2. Process with Gemini
    try {
      List<Part> promptParts = [];
      
      if (text.isNotEmpty) {
        promptParts.add(TextPart(text));
      } else if (currentFile != null) {
        promptParts.add(TextPart("Please review this document."));
      }
      
      // If a file was attached, append it as a DataPart
      if (currentFile != null && currentFile.bytes != null) {
        final mimeType = _resolveMimeType(currentFile.extension);
        promptParts.add(DataPart(mimeType, currentFile.bytes!));
      }

      // Send the multimodal payload
      final response = await _chatSession.sendMessage(Content.multi(promptParts));

      // 3. Update UI with AI Response
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.insert(0, ChatMessage(
            text: response.text ?? "I couldn't process that request.",
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Gemini error: $e');
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.insert(0, ChatMessage(
            text: _geminiKey.isEmpty
                ? "The AI assistant isn't configured yet (missing API key)."
                : "I couldn't reach the AI service right now. Please try again in a moment.",
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), 
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1B4D2C),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.support_agent_rounded, color: Color(0xFF2D7D46)), 
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Telmed Assistant",
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  "Online & Ready",
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Chat Area
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              reverse: true, 
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isTyping && index == 0) {
                  return const _TypingIndicator();
                }
                
                final msgIndex = _isTyping ? index - 1 : index;
                final message = _messages[msgIndex];
                
                return _ChatBubble(message: message);
              },
            ),
          ),

          // Input Area
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, -5),
            blurRadius: 20,
          )
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_selectedFile != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFE53935)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedFile!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          Text(
                            _formatBytes(_selectedFile!.size),
                            style: const TextStyle(color: Colors.black54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: Colors.black54),
                      onPressed: _clearSelectedFile,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],

            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF64748B)),
                  onPressed: _pickDocument,
                  tooltip: "Attach PDF or Image",
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: "Describe your symptoms or attach a document...",
                        hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _sendMessage,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF2D7D46), Color(0xFF4CAF50)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (bytes > 0) ? (bytes.bitLength - 1) ~/ 10 : 0;
    return '${(bytes / (1 << (i * 10))).toStringAsFixed(1)} ${suffixes[i]}';
  }
}

// --- CHAT BUBBLE WIDGET ---
class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(message.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!message.isUser) ...[
            const CircleAvatar(
              backgroundColor: Color(0xFFE8F5E9),
              radius: 16,
              child: Icon(Icons.support_agent_rounded, size: 18, color: Color(0xFF2D7D46)), 
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: message.isUser ? const Color(0xFF2D7D46) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(message.isUser ? 20 : 4),
                  bottomRight: Radius.circular(message.isUser ? 4 : 20),
                ),
                boxShadow: [
                  if (!message.isUser)
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.hasAttachment) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: EdgeInsets.only(bottom: message.text.isNotEmpty ? 12 : 0),
                      decoration: BoxDecoration(
                        color: message.isUser ? Colors.white.withOpacity(0.15) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.insert_drive_file_rounded,
                            color: message.isUser ? Colors.white : const Color(0xFF2D7D46),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              message.attachedFileName ?? "Document",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: message.isUser ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (message.text.isNotEmpty)
                    Text(
                      message.text,
                      style: GoogleFonts.plusJakartaSans(
                        color: message.isUser ? Colors.white : const Color(0xFF1E293B),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  
                  const SizedBox(height: 6),
                  
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: message.isUser ? Colors.white.withOpacity(0.7) : Colors.black45,
                        ),
                      ),
                      if (message.isUser) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.done_all_rounded, size: 14, color: Colors.white.withOpacity(0.7)),
                      ]
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- TYPING INDICATOR WIDGET ---
class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFE8F5E9),
            radius: 16,
            child: Icon(Icons.support_agent_rounded, size: 18, color: Color(0xFF2D7D46)), 
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _JumpingDot(delay: 0),
                SizedBox(width: 4),
                _JumpingDot(delay: 200),
                SizedBox(width: 4),
                _JumpingDot(delay: 400),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JumpingDot extends StatefulWidget {
  final int delay;
  const _JumpingDot({required this.delay});

  @override
  State<_JumpingDot> createState() => _JumpingDotState();
}

class _JumpingDotState extends State<_JumpingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -5 * _controller.value),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF2D7D46),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}