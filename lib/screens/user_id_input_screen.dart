import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/my_app.dart';

class UserIdInputScreen extends StatefulWidget {
  const UserIdInputScreen({Key? key}) : super(key: key);

  @override
  _UserIdInputScreenState createState() => _UserIdInputScreenState();
}

class _UserIdInputScreenState extends State<UserIdInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userIdController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkExistingUserId();
  }

  Future<void> _checkExistingUserId() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('user_id') != null) _navigateToMainApp();
  }

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Image.asset('assets/background.jpg', fit: BoxFit.cover),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 350),
                child: Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            controller: _userIdController,
                            decoration: InputDecoration(
                              labelText: 'User ID',
                              prefixIcon: const Icon(Icons.person_outline),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.cyan)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.cyan)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.cyan)),
                            ),
                            validator: (value) => value == null || value.isEmpty ? 'Пожалуйста, введите User ID' : null,
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan[800], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                              onPressed: _saveUserId,
                              child: const Text('Продолжить', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveUserId() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', _userIdController.text.trim());
      _navigateToMainApp();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e'), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _navigateToMainApp() {
    Navigator.of(context).pushReplacement(PageRouteBuilder(pageBuilder: (_, __, ___) => const MyApp(), transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c)));
  }
}