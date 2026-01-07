import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _logoController;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoFadeAnimation;
  
  late AnimationController _transitionController;
  late Animation<Offset> _logoMoveAnimation;
  late Animation<double> _loginSlideAnimation;
  late Animation<double> _loginFadeAnimation;

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  
  String _selectedRole = 'admin';
  bool _isLoading = false;
  bool _showLoginForm = false;

  @override
  void initState() {
    super.initState();
    
    // Phase 1: Logo Entry (Super Speed)
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _logoScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeIn),
    );

    // Phase 2 & 3: Logo Movement & Login Slide-up
    _transitionController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _logoMoveAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.32), // Move to top third but stay visible
    ).animate(CurvedAnimation(
      parent: _transitionController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeInOutCubic),
    ));

    _loginSlideAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOutBack),
      ),
    );

    _loginFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _transitionController,
        curve: const Interval(0.4, 0.8, curve: Curves.easeIn),
      ),
    );

    _startSequence();
  }

  Future<void> _startSequence() async {
    // 1. Logo Entry
    await _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Check if user is already logged in
    final user = await _authService.getCurrentUser();
    if (user != null) {
      // If logged in, just go home
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } else {
      // 2. Start Transition to Login
      setState(() => _showLoginForm = true);
      await _transitionController.forward();
    }
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      
      final user = await _authService.login(
        _usernameController.text,
        _passwordController.text,
        _selectedRole,
      );

      setState(() => _isLoading = false);

      if (user != null) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid credentials')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _transitionController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image with Overlay
          Positioned.fill(
            child: Image.asset(
              'assets/images/hospital_bg.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.4), // Darken for readability
            ),
          ),

          // Logo Animation
          Center(
            child: AnimatedBuilder(
              animation: _transitionController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _logoMoveAnimation.value.dy * MediaQuery.of(context).size.height),
                  child: ScaleTransition(
                    scale: _logoScaleAnimation,
                    child: FadeTransition(
                      opacity: _logoFadeAnimation,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 20,
                                )
                              ],
                            ),
                            child: Image.asset(
                              'assets/icon/app_icon.png',
                              width: 80,
                              height: 80,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'ThermalVision AI',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontFamily: 'Gilroy',
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Sliding Login Form
          if (_showLoginForm)
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedBuilder(
                animation: _transitionController,
                builder: (context, child) {
                  return FractionalTranslation(
                    translation: Offset(0, _loginSlideAnimation.value),
                    child: FadeTransition(
                      opacity: _loginFadeAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(40),
                            topRight: Radius.circular(40),
                          ),
                        ),
                        child: _buildLoginForm(),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Secure Access',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
                fontFamily: 'Gilroy',
              ),
            ),
            const Text(
              'Please login to continue to ICU monitor',
              style: TextStyle(color: Color(0xFF64748B), fontFamily: 'Gilroy'),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
              ),
              validator: (value) => value!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock, color: Theme.of(context).colorScheme.primary),
              ),
              validator: (value) => value!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: InputDecoration(
                labelText: 'Role',
                prefixIcon: Icon(Icons.badge, color: Theme.of(context).colorScheme.primary),
              ),
              items: const [
                DropdownMenuItem(value: 'admin', child: Text('Administrator')),
                DropdownMenuItem(value: 'user', child: Text('Nurse/User')),
              ],
              onChanged: (value) => setState(() => _selectedRole = value!),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Login',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Gilroy'),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Forgot your password?',
                style: TextStyle(color: Color(0xFF64748B), fontFamily: 'Gilroy'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
