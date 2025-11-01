import 'package:flutter/material.dart';

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.teal)),
            SizedBox(height: 16),
            Text('Загрузка...', style: TextStyle(fontSize: 16, color: Colors.teal)),
          ],
        ),
      ),
    );
  }
}