import 'package:flutter/material.dart';
import '../cloud/firebase_service.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  String? _error;
  bool _isLogin = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    if (!firebaseService.isInitialized) {
      setState(() {
        _error = 'Firebase ยังไม่พร้อม (แอพยังใช้งานออฟไลน์ได้)';
        _busy = false;
      });
      return;
    }
    String? err;
    if (_isLogin) {
      err = await firebaseService.signInWithEmail(_email.text.trim(), _pass.text);
    } else {
      err = await firebaseService.signUpWithEmail(
        _email.text.trim(), _pass.text, displayName: _name.text.trim(),
      );
    }
    setState(() { _error = err; _busy = false; });
    if (err == null && mounted) Navigator.pop(context); // ปิดหน้าเมื่อสำเร็จ
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = firebaseService.isSignedIn;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: signedIn ? _signedInView(context) : _formView(context),
      ),
    );
  }

  Widget _signedInView(BuildContext context) {
    final u = firebaseService.currentUser!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Signed in as', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(u.email ?? u.uid),
        const SizedBox(height: 8),
        Text('Display name: ${u.displayName ?? '-'}'),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.tonal(
              onPressed: () async {
                await firebaseService.saveUserProfile({
                  'uid': u.uid,
                  'email': u.email,
                  'displayName': u.displayName,
                  'updatedAt': DateTime.now().toUtc(),
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Saved profile to cloud')),
                  );
                }
              },
              child: const Text('Save Profile to Cloud'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () async { await firebaseService.signOut(); setState(() {}); },
              child: const Text('Sign out'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(firebaseService.isOnline ? Icons.cloud_done : Icons.cloud_off),
            const SizedBox(width: 8),
            Text(firebaseService.isOnline ? 'Online' : 'Offline'),
          ],
        ),
      ],
    );
  }

  Widget _formView(BuildContext context) {
    return Column(
      children: [
        if (!_isLogin)
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
        TextField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
        ),
        TextField(
          controller: _pass,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
        ),
        const SizedBox(height: 12),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_isLogin ? 'Sign in' : 'Sign up'),
        ),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _isLogin = !_isLogin),
          child: Text(_isLogin ? 'Create an account' : 'I have an account'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(firebaseService.isOnline ? Icons.cloud_done : Icons.cloud_off),
            const SizedBox(width: 8),
            Text(firebaseService.isOnline ? 'Online' : 'Offline'),
          ],
        ),
        if (!firebaseService.isInitialized)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Tip: ตั้งค่า Firebase ภายหลังได้ แอพยังทำงานออฟไลน์ได้'),
          ),
      ],
    );
  }
}
