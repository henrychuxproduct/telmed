import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'dart:async';

import '../utils/responsive.dart';

// FIXED IMPORTS: Since these files are in the same folder (lib/widgets/), 
// we just import them by name.
import 'join_overlay.dart';
import 'package:telmed/pages/rx_verification_scanner.dart'; // Imported the scanner page

/// --- FLEXIBLE BRAND LOGO ---
class BrandLogo extends StatelessWidget {
  final bool isDark;
  final double height;
  final bool showName;

  const BrandLogo({
    super.key, 
    this.isDark = true, 
    this.height = 40.0,
    this.showName = false, 
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/logo.webp',
          height: height,
          fit: BoxFit.contain,
          errorBuilder: (c, o, s) => Icon(Icons.health_and_safety, color: isDark ? const Color(0xFF2D7D46) : Colors.white, size: height),
        ),
        if (showName) ...[
          const SizedBox(width: 12),
          Text(
            "TELMED",
            style: GoogleFonts.plusJakartaSans(
              fontSize: height * 0.6,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: isDark ? const Color(0xFF2D7D46) : Colors.white,
            ),
          ),
        ],
      ],
    );
  }
}

class TelmedNavBar extends StatelessWidget {
  final double navOpacity;
  const TelmedNavBar({super.key, required this.navOpacity});

  @override
  Widget build(BuildContext context) {
    final bool isScrolled = navOpacity > 0.5;
    final double screenWidth = MediaQuery.of(context).size.width;

    // Full inline menu only where it really fits (>= 1024). Phones AND
    // tablets get the compact bar + drawer, so nothing overflows in between.
    final bool isDesktop = Responsive.isDesktop(context);
    final bool showCompactCta = !isDesktop && screenWidth >= 420;

    final double hPad = screenWidth < 600 ? 20 : (screenWidth < 1280 ? 32 : 60);
    final double itemPad = screenWidth < 1200 ? 12 : 20;

    return Positioned(
      top: 0, left: 0, right: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10 * navOpacity, sigmaY: 10 * navOpacity),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(navOpacity * 0.8),
              border: Border(bottom: BorderSide(color: isScrolled ? Colors.black12 : Colors.transparent)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  BrandLogo(
                    isDark: isScrolled,
                    height: 35,
                    showName: true,
                  ),
                  const Spacer(),
                  if (isDesktop) ...[
                    _navItem("Services", isScrolled, itemPad),
                    _navItem("Homecare", isScrolled, itemPad),
                    _navItem("Pricing", isScrolled, itemPad),
                    const SizedBox(width: 24),

                    // --- TESTING BUTTON FOR DOCTORS ---
                    const DoctorTestBtn(),
                    const SizedBox(width: 15),

                    // --- VERIFY RX SCANNER BUTTON ---
                    const VerifyRxBtn(),
                    const SizedBox(width: 15),

                    _getStartedButton(context),
                  ] else ...[
                    if (showCompactCta) _getStartedButton(context),

                    // --- MENU ICON (phones + tablets) ---
                    IconButton(
                      icon: Icon(Icons.menu, color: isScrolled ? Colors.black : Colors.white),
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _getStartedButton(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        // Routing to the auth page
        Navigator.pushNamed(context, '/auth');
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2D7D46),
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      ),
      child: const Text("Get Started", style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _navItem(String label, bool isScrolled, double horizontalPadding) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Text(
        label,
        style: TextStyle(
          color: isScrolled ? Colors.black87 : Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 15
        ),
      ),
    );
  }
}

/// --- DOCTOR TESTING BUTTON ---
class DoctorTestBtn extends StatelessWidget {
  const DoctorTestBtn({super.key});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const JoinOverlay(),
        );
      },
      icon: const Icon(Icons.medical_services_outlined, size: 18),
      label: const Text("Doctor Test"),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF2D7D46),
        side: const BorderSide(color: Color(0xFF2D7D46)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      ),
    );
  }
}

/// --- VERIFY RX BUTTON ---
class VerifyRxBtn extends StatelessWidget {
  const VerifyRxBtn({super.key});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RxVerificationScanner()),
        );
      },
      icon: const Icon(Icons.qr_code_scanner, size: 18),
      label: const Text("Verify RX"),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFF9A825), // Uses the Gold CTA color to stand out slightly
        side: const BorderSide(color: Color(0xFFF9A825)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      ),
    );
  }
}

class ActionBtn extends StatelessWidget {
  final String label;
  final String? iconUrl;
  final IconData? iconData;
  final Color color;
  final bool primary;
  final VoidCallback? onTap; // NEW: Added optional custom tap handler

  const ActionBtn({
    super.key,
    required this.label,
    this.iconUrl,
    this.iconData,
    required this.color,
    required this.primary,
    this.onTap, // NEW: Include in constructor
  });

  @override
  Widget build(BuildContext context) {
    final bool isMobile = Responsive.isMobile(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        // NEW: If onTap is provided, use it. Otherwise, default to CallOverlay
        // The default used to open the call screen with NO payment check
        // (e.g. "Book a Home Visit" gave a free call). Calls now only start
        // from the verified M-Pesa flow on the home page.
        onTap: onTap ?? () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Home visit booking is coming soon.")),
          );
        },
        child: Container(
          height: 60,
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 25),
          decoration: BoxDecoration(
            color: primary ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
            border: primary ? null : Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (iconUrl != null) Image.network(iconUrl!, height: 22, width: 22),
              if (iconData != null) Icon(iconData, color: primary ? Colors.white : const Color(0xFFF9A825), size: 20),
              const SizedBox(width: 12),
              // Flexible + ellipsis: on a very narrow screen the label shrinks
              // instead of throwing a RenderFlex overflow.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TelmedFooter extends StatelessWidget {
  const TelmedFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 20),
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          const BrandLogo(isDark: false, height: 60, showName: false),
          const SizedBox(height: 30),
          Text(
            "Quality healthcare, just a call away.",
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16),
          ),
          const SizedBox(height: 50),
          const Divider(color: Colors.white10),
          const SizedBox(height: 30),
          Text(
            "© ${DateTime.now().year} Telmed Inc. All rights reserved.",
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// --- DRAWER COMPONENT ---
class TelmedDrawer extends StatelessWidget {
  const TelmedDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Color(0xFF1B4D2C)),
            child: Center(child: BrandLogo(isDark: false, height: 50, showName: true)),
          ),
          _drawerItem(context, Icons.medical_services_outlined, "Services", () {}),
          _drawerItem(context, Icons.home_work_outlined, "Homecare", () {}),
          _drawerItem(context, Icons.payments_outlined, "Pricing", () {}),
          const Divider(),
          
          // --- REPLACED: Get Started instead of Doctor Login ---
          _drawerItem(context, Icons.person_add_outlined, "Get Started", () {
            Navigator.pop(context); // Closes drawer nicely
            Navigator.pushNamed(context, '/auth'); // Route to auth page
          }),
          
          // --- SMOOTH MOBILE DOCTOR TEST BUTTON ---
          _drawerItem(context, Icons.video_camera_front_outlined, "Doctor Test (Join)", () {
            // Smoothly close the drawer first before showing the video overlay
            Navigator.pop(context); 
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const JoinOverlay(),
            );
          }),

          // --- MOBILE DRAWER ITEM FOR RX SCANNER ---
          _drawerItem(context, Icons.qr_code_scanner, "Verify RX (Scanner)", () {
            // Smoothly close the drawer first
            Navigator.pop(context);
            // Then route them to the scanning page
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const RxVerificationScanner()),
            );
          }),
        ],
      ),
    );
  }

  Widget _drawerItem(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF2D7D46)),
      title: Text(title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}

// --- IMPROVED ANIMATED TYPEWRITER WIDGET ---
class TypewriterPrompt extends StatefulWidget {
  final Color baseColor; // The "Tap:" color
  final Color accentColor; // The "Tell Med" color (e.g. Gold)

  const TypewriterPrompt({
    super.key, 
    this.baseColor = Colors.white,
    this.accentColor = const Color(0xFFF9A825), // Telmed Gold
  });

  @override
  State<TypewriterPrompt> createState() => _TypewriterPromptState();
}

class _TypewriterPromptState extends State<TypewriterPrompt> with SingleTickerProviderStateMixin {
  // BRANDING: Specifically "Tell Med" to match website name
  final List<String> _phrases = ["Tell us...", "Tell Med."];
  
  int _currentPhraseIndex = 0;
  String _displayedText = "";
  bool _isBackspacing = false;
  Timer? _timer;
  
  // Cursor Blinking Animation
  late AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    
    _startTyping();
  }

  void _startTyping() {
    // Speed adjusted: Faster typing (80ms), slower backspacing (50ms)
    _timer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (!mounted) return;

      setState(() {
        String fullPhrase = _phrases[_currentPhraseIndex];

        if (_isBackspacing) {
          if (_displayedText.isNotEmpty) {
            _displayedText = _displayedText.substring(0, _displayedText.length - 1);
          } else {
            _isBackspacing = false;
            _currentPhraseIndex = (_currentPhraseIndex + 1) % _phrases.length;
          }
        } else {
          if (_displayedText.length < fullPhrase.length) {
            _displayedText = fullPhrase.substring(0, _displayedText.length + 1);
          } else {
            // Finished typing phrase.
            // If it's "Tell Med.", hold it longer for branding effect.
            int pauseDuration = fullPhrase.contains("Med") ? 3000 : 1500;
            
            _timer?.cancel();
            Future.delayed(Duration(milliseconds: pauseDuration), () {
              if (mounted) {
                setState(() => _isBackspacing = true);
                _startTyping();
              }
            });
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // "Tap:" Part
          Text(
            "Tap: ",
            style: GoogleFonts.plusJakartaSans(
              color: widget.baseColor.withOpacity(0.9),
              fontWeight: FontWeight.w600,
              fontSize: 16, // Slightly larger for compelling look
            ),
          ),
          
          // "Tell Med" Part (Branded Color)
          Text(
            _displayedText,
            style: GoogleFonts.plusJakartaSans(
              color: widget.accentColor, // Gold color to be "tasty"
              fontWeight: FontWeight.w800, // Bold branding
              fontSize: 16,
              letterSpacing: 0.5,
            ),
          ),
          
          // Blinking Cursor
          FadeTransition(
            opacity: _cursorController,
            child: Container(
              margin: const EdgeInsets.only(left: 2, bottom: 4),
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: widget.accentColor,
                borderRadius: BorderRadius.circular(2)
              ),
            ),
          )
        ],
      ),
    );
  }
}