import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telmed/services/auth_service.dart'; // IMPORTED YOUR AUTH SERVICE

// IMPORT COMMON WIDGETS
// Ensure this path matches where your common_widget.dart is located.
import '../widgets/common_widget.dart'; 

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  // FormKey for validation
  final _formKey = GlobalKey<FormState>();

  // Initialize the Auth Service
  final AuthService _authService = AuthService();

  // Scroll logic for NavBar
  late ScrollController _scrollController;
  double _navOpacity = 0.0;

  bool _isSignIn = true;
  bool _isLoading = false; 
  String _selectedRole = 'patient'; // 'patient', 'doctor', 'pharmacy'
  
  // State variable to hold and display server errors
  String? _serverError; 

  // Password visibility states
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Scroll listener for dynamic navbar opacity
    _scrollController = ScrollController()
      ..addListener(() {
        if (mounted) {
          setState(() {
            _navOpacity = (_scrollController.offset / 400).clamp(0.0, 1.0);
          });
        }
      });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 850;

    return Scaffold(
      // CHANGED: Initial background is now Dark Green so navbar links pop
      backgroundColor: const Color(0xFF1B4D2C), 
      endDrawer: const TelmedDrawer(), 
      body: Stack(
        children: [
          // 1. MAIN SCROLLABLE CONTENT
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                // Spacer to prevent content from hiding behind the floating navbar
                const SizedBox(height: 100),
                
                // Main layout area
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: size.height - 100, 
                  ),
                  child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
                ),

                // 2. THE FOOTER
                const TelmedFooter(),
              ],
            ),
          ),

          // 3. THE FLOATING NAVBAR
          TelmedNavBar(navOpacity: _navOpacity),
        ],
      ),
    );
  }

  // ==========================================
  // LAYOUTS
  // ==========================================

  Widget _buildDesktopLayout() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LEFT SIDE - Branding Details
          Expanded(
            flex: 1,
            child: Stack(
              children: [
                Positioned(
                  top: -100, left: -100,
                  child: Container(
                    width: 400, height: 400,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF2D7D46).withOpacity(0.4),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -50, right: -50,
                  child: Container(
                    width: 300, height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF9A825).withOpacity(0.15),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(60.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Digital Healthcare,\nSimplified.",
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w800, height: 1.1),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Join our network of patients, certified doctors, and verified pharmacies for seamless medical care.",
                        style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 18, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // RIGHT SIDE - Form inside a white card
          Expanded(
            flex: 1,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15), 
                          blurRadius: 40, 
                          offset: const Offset(0, 15)
                        )
                      ],
                    ),
                    child: _buildForm(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Digital Healthcare,\nSimplified.",
            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, height: 1.2),
          ),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 10))
              ],
            ),
            child: _buildForm(),
          ),
          const SizedBox(height: 40), // Bottom padding before footer
        ],
      ),
    );
  }

  // ==========================================
  // FORM COMPONENTS
  // ==========================================

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isSignIn ? "Welcome Back" : "Create Account",
            style: GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Text(
            _isSignIn ? "Enter your details to access your portal." : "Join Telmed to get started.",
            style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B), fontSize: 16),
          ),
          const SizedBox(height: 25),

          // THE SERVER ERROR BANNER
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _serverError != null
                ? Container(
                    margin: const EdgeInsets.only(bottom: 25),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _serverError!,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.red.shade800, 
                              fontWeight: FontWeight.w600, 
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // Entity Selector (Only show on Sign Up)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: !_isSignIn
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("I AM A:", style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF64748B), letterSpacing: 1.2)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildRoleCard('patient', Icons.person_outline, "Patient")),
                          const SizedBox(width: 10),
                          Expanded(child: _buildRoleCard('doctor', Icons.medical_services_outlined, "Doctor")),
                          const SizedBox(width: 10),
                          Expanded(child: _buildRoleCard('pharmacy', Icons.local_pharmacy_outlined, "Pharmacy")),
                        ],
                      ),
                      const SizedBox(height: 25),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          // Inputs
          if (!_isSignIn) ...[
            _buildInputLabel(_selectedRole == 'pharmacy' ? "Pharmacy Name" : "Full Name"),
            _buildTextField(
              controller: _nameController,
              hint: _selectedRole == 'pharmacy' ? "e.g. Good Health Pharmacy" : "e.g. Dr. John Doe",
              icon: Icons.badge_outlined,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return _selectedRole == 'pharmacy' ? 'Please enter your pharmacy name' : 'Please enter your full name';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
          ],

          _buildInputLabel("Email Address"),
          _buildTextField(
            controller: _emailController,
            hint: "you@example.com",
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your email';
              }
              if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(value)) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          _buildInputLabel("Password"),
          _buildTextField(
            controller: _passwordController,
            hint: "••••••••",
            icon: Icons.lock_outline,
            isPassword: true,
            obscureText: _obscurePassword,
            onToggleVisibility: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your password';
              }
              if (!_isSignIn && value.length < 6) {
                return 'Password must be at least 6 characters long';
              }
              return null;
            },
          ),

          if (!_isSignIn) ...[
            const SizedBox(height: 20),
            _buildInputLabel("Confirm Password"),
            _buildTextField(
              controller: _confirmPasswordController,
              hint: "••••••••",
              icon: Icons.lock_outline,
              isPassword: true,
              obscureText: _obscureConfirmPassword,
              onToggleVisibility: () {
                setState(() {
                  _obscureConfirmPassword = !_obscureConfirmPassword;
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please confirm your password';
                }
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
          ],

          if (_isSignIn) ...[
            const SizedBox(height: 15),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  final String email = _emailController.text.trim();
                  if (email.isEmpty) {
                    setState(() => _serverError = 'Enter your email above first, then tap "Forgot Password?".');
                    return;
                  }
                  final String? err = await _authService.sendPasswordReset(email);
                  if (!mounted) return;
                  if (err != null) {
                    setState(() => _serverError = err);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF2D7D46),
                        content: Text("If an account exists for $email, a reset link has been sent."),
                      ),
                    );
                  }
                },
                child: Text("Forgot Password?", style: GoogleFonts.plusJakartaSans(color: const Color(0xFF2D7D46), fontWeight: FontWeight.bold)),
              ),
            ),
          ] else ...[
            const SizedBox(height: 30),
          ],

          // Submit Button
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: _isLoading ? null : () async {
                setState(() { _serverError = null; });

                if (_formKey.currentState!.validate()) {
                  FocusScope.of(context).unfocus(); 
                  setState(() => _isLoading = true);
                  
                  String? errorMessage;

                  if (_isSignIn) {
                    errorMessage = await _authService.signIn(
                      email: _emailController.text.trim(),
                      password: _passwordController.text.trim(),
                    );
                  } else {
                    errorMessage = await _authService.signUp(
                      email: _emailController.text.trim(),
                      password: _passwordController.text.trim(),
                      name: _nameController.text.trim(),
                      role: _selectedRole,
                    );
                  }

                  if (!mounted) return;

                  if (errorMessage != null) {
                    setState(() { 
                      _isLoading = false;
                      _serverError = errorMessage;
                    });
                  } else {
                    // ==========================================
                    // ROLE-BASED ROUTING LOGIC
                    // ==========================================
                    final user = _authService.currentUser;
                    
                    if (user != null) {
                      String? userRole = !_isSignIn ? _selectedRole : await _authService.getUserRole(user.uid);
                      
                      if (!mounted) return;
                      setState(() => _isLoading = false);

                      // Final Routing Check
                      if (userRole == 'patient') {
                        Navigator.pushReplacementNamed(context, '/home'); 
                      } else if (userRole == 'doctor') {
                        Navigator.pushReplacementNamed(context, '/doctor_home'); 
                      } else if (userRole == 'pharmacy') {
                        Navigator.pushReplacementNamed(context, '/pharmacy_home'); 
                      } else {
                        setState(() { _serverError = "User role undefined. Please contact support."; });
                      }
                    } else {
                      setState(() { 
                        _isLoading = false;
                        _serverError = "Failed to retrieve user session."; 
                      });
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF9A825), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
                disabledBackgroundColor: const Color(0xFFF9A825).withOpacity(0.7), 
              ),
              child: _isLoading 
                ? const SizedBox(
                    height: 24, 
                    width: 24, 
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                  )
                : Text(
                    _isSignIn ? "SIGN IN" : "CREATE ACCOUNT",
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                  ),
            ),
          ),

          const SizedBox(height: 30),

          // Toggle Sign In / Sign Up
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _isSignIn ? "Don't have an account? " : "Already have an account? ",
                style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B)),
              ),
              GestureDetector(
                onTap: () {
                  _formKey.currentState?.reset();
                  _nameController.clear();
                  _emailController.clear();
                  _passwordController.clear();
                  _confirmPasswordController.clear();
                  setState(() {
                    _isSignIn = !_isSignIn;
                    _serverError = null; 
                    _obscurePassword = true;
                    _obscureConfirmPassword = true;
                  });
                },
                child: Text(
                  _isSignIn ? "Sign Up" : "Sign In",
                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFF2D7D46), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // HELPERS
  // ==========================================

  Widget _buildRoleCard(String role, IconData icon, String label) {
    bool isSelected = _selectedRole == role;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2D7D46) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? const Color(0xFF2D7D46) : const Color(0xFFE2E8F0), width: 2),
          boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF2D7D46).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))] : [],
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.white : const Color(0xFF64748B), size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: isSelected ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller, 
    required String hint, 
    required IconData icon, 
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
      onChanged: (val) {
        if (_serverError != null) {
          setState(() => _serverError = null);
        }
      },
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontWeight: FontWeight.normal),
        prefixIcon: Icon(icon, color: const Color(0xFF94A3B8)),
        suffixIcon: isPassword 
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: const Color(0xFF94A3B8),
                ),
                onPressed: onToggleVisibility,
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2D7D46), width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 2.0),
        ),
      ),
    );
  }
}