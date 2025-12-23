import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF2E2A25),
              Color(0xFF1E1B18),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFFBE9D7),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.storefront,
                size: 68,
                color: Color(0xFFF57C00),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Kokonuts POS',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Checking activation status...',
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFFE0DDD9),
              ),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF57C00)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
