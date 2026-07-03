// login_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jeevanlink/home_page.dart';
import 'package:jeevanlink/signup_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:crypt/crypt.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LoginUserRole { donor, hospital }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  LoginUserRole _selectedRole = LoginUserRole.donor;

  // Donor-specific controllers
  final _phoneController = TextEditingController();

  // Hospital-specific controllers  
  final _emailController = TextEditingController();

  // OTP related variables
  bool _showOtpVerification = false;
  List<TextEditingController> _otpControllers = List.generate(6, (index) => TextEditingController());
  List<FocusNode> _otpFocusNodes = List.generate(6, (index) => FocusNode());
  String? _pendingPhone;

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _otpFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        if (_selectedRole == LoginUserRole.donor) {
          await _signInDonor();
        } else {
          await _signInHospital();
        }
      } on AuthException catch (e) {
        if (mounted) {
          print('AuthException: ${e.message}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Login Failed: ${e.message}')),
          );
        }
      } catch (e) {
        if (mounted) {
          print('General Exception: ${e.toString()}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('An unexpected error occurred: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _signInDonor() async {
    final phone = '+91${_phoneController.text.trim().replaceAll(RegExp(r'[\s-]'), '')}';
    final password = _passwordController.text.trim();

    print('Donor login with phone: $phone');

    // Fetch profile directly from profiles table
    final profile = await Supabase.instance.client
        .from('profiles')
        .select()
        .eq('phone', phone)
        .eq('role', 'donor')
        .maybeSingle();

    if (profile == null) {
      throw Exception('Account not found. Please sign up first.');
    }

    // Verify password
    final storedHash = profile['password'] as String?;
    if (storedHash == null || storedHash.isEmpty) {
      throw Exception('Invalid account data. Please contact support.');
    }

    final isPasswordValid = Crypt(storedHash).match(password);

    if (isPasswordValid) {
      // Login successful - Save session locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_phone', phone);
      await prefs.setString('user_role', 'donor');
      await prefs.setString('user_id', profile['id']);

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomePage()),
          (route) => false,
        );
      }
    } else {
      throw Exception('Incorrect password');
    }
  }

  Future<void> _signInHospital() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    print('Hospital login with email: $email');

    final AuthResponse res = await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (mounted && res.user != null) {
      // Check if user's email is confirmed
      if (res.user!.emailConfirmedAt == null) {
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please verify your email address before signing in.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Check if user profile exists
      var profile = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', res.user!.id)
          .maybeSingle();

      // If profile doesn't exist, create it from user metadata
      if (profile == null) {
        print('Profile not found, creating from user metadata...');
        
        final userMetadata = res.user!.userMetadata ?? {};
        if (userMetadata['role'] == 'hospital') {
          try {
            await Supabase.instance.client.from('profiles').insert({
              'id': res.user!.id,
              'role': 'hospital',
              'hospital_name': userMetadata['hospital_name'],
              'latitude': userMetadata['latitude'],
              'longitude': userMetadata['longitude'],
              'created_at': DateTime.now().toIso8601String(),
            });

            // Fetch the newly created profile
            profile = await Supabase.instance.client
                .from('profiles')
                .select()
                .eq('id', res.user!.id)
                .single();
          } catch (e) {
            print('Error creating profile: $e');
            await Supabase.instance.client.auth.signOut();
            throw Exception('Failed to create user profile');
          }
        } else {
          await Supabase.instance.client.auth.signOut();
          throw Exception('Invalid hospital account data');
        }
      }

      // Verify it's a hospital profile
      if (profile != null && profile['role'] == 'hospital') {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomePage()),
          (route) => false,
        );
      } else {
        await Supabase.instance.client.auth.signOut();
        throw Exception('This account is not registered as a hospital');
      }
    }
  }

  Future<void> _verifyOtp() async {
    String otp = _otpControllers.map((controller) => controller.text).join();
    
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter all 6 digits'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final AuthResponse res = await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.sms,
        token: otp,
        phone: _pendingPhone,
      );

      if (mounted && res.user != null) {
        // Check if user profile exists and is a donor
        final profile = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', res.user!.id)
            .eq('role', 'donor')
            .maybeSingle();

        if (profile != null) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomePage()),
            (route) => false,
          );
        } else {
          await Supabase.instance.client.auth.signOut();
          throw Exception('Invalid donor account or profile not found');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification Failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resendOtp() async {
    if (_pendingPhone == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.sms,
        phone: _pendingPhone!,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP resent successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resend OTP: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _goBackToLogin() {
    setState(() {
      _showOtpVerification = false;
      _pendingPhone = null;
      for (var controller in _otpControllers) {
        controller.clear();
      }
    });
  }

  Widget _buildOtpBox(int index) {
    return Container(
      width: 45,
      height: 55,
      child: TextFormField(
        controller: _otpControllers[index],
        focusNode: _otpFocusNodes[index],
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold),
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.grey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.redAccent, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.grey),
          ),
          contentPadding: const EdgeInsets.all(0),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            _otpFocusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _otpFocusNodes[index - 1].requestFocus();
          }
        },
      ),
    );
  }

  Widget _buildOtpVerificationUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Verify Phone Number',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.redAccent,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the 6-digit code sent to\n${_pendingPhone ?? ''}',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey),
        ),
        const SizedBox(height: 40),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, (index) => _buildOtpBox(index)),
        ),
        
        const SizedBox(height: 30),
        
        _isLoading
            ? const Center(child: SpinKitFadingCircle(color: Colors.redAccent))
            : ElevatedButton(
                onPressed: _verifyOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'Verify & Sign In',
                  style: GoogleFonts.poppins(fontSize: 18, color: Colors.white),
                ),
              ),
        
        const SizedBox(height: 20),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Didn't receive code? ",
              style: GoogleFonts.poppins(color: Colors.grey),
            ),
            TextButton(
              onPressed: _isLoading ? null : _resendOtp,
              child: Text(
                'Resend',
                style: GoogleFonts.poppins(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 10),
        
        TextButton(
          onPressed: _goBackToLogin,
          child: Text(
            'Back to Login',
            style: GoogleFonts.poppins(
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginUI() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Welcome Back',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to continue saving lives',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 30),
          
          SegmentedButton<LoginUserRole>(
            style: SegmentedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              selectedForegroundColor: Colors.white,
              selectedBackgroundColor: Colors.red,
            ),
            segments: <ButtonSegment<LoginUserRole>>[
              ButtonSegment<LoginUserRole>(
                value: LoginUserRole.donor,
                label: Text('Donor', style: GoogleFonts.poppins()),
                icon: const Icon(Icons.person),
              ),
              ButtonSegment<LoginUserRole>(
                value: LoginUserRole.hospital,
                label: Text('Requestor', style: GoogleFonts.poppins()),
                icon: const Icon(Icons.local_hospital),
              ),
            ],
            selected: <LoginUserRole>{_selectedRole},
            onSelectionChanged: (Set<LoginUserRole> newSelection) {
              setState(() {
                _selectedRole = newSelection.first;
                _phoneController.clear();
                _emailController.clear();
                _passwordController.clear();
              });
            },
          ),
          
          const SizedBox(height: 30),
          
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _selectedRole == LoginUserRole.donor
                ? Column(
                    key: const ValueKey('donor-fields'),
                    children: [
                      TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone_android),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your phone number';
                          }
                          if (value.length < 10) {
                            return 'Please enter a valid phone number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          return null;
                        },
                      ),
                    ],
                  )
                : Column(
                    key: const ValueKey('hospital-fields'),
                    children: [
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Hospital Email',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter email';
                          }
                          if (!value.contains('@')) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter password';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
          ),
          
          const SizedBox(height: 30),
          
          _isLoading
              ? const Center(child: SpinKitFadingCircle(color: Colors.redAccent))
              : ElevatedButton(
                  onPressed: _signIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Sign In',
                    style: GoogleFonts.poppins(fontSize: 18, color: Colors.white),
                  ),
                ),
          
          const SizedBox(height: 20),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Don't have an account? ",
                style: GoogleFonts.poppins(color: Colors.grey),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => const SignUpPage()));
                },
                child: Text(
                  'Sign Up',
                  style: GoogleFonts.poppins(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _showOtpVerification ? AppBar(
        title: Text('Verify OTP', style: GoogleFonts.poppins()),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBackToLogin,
          color: Colors.black,
        ),
      ) : null,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _showOtpVerification 
                ? _buildOtpVerificationUI()
                : _buildLoginUI(),
          ),
        ),
      ),
    );
  }
}