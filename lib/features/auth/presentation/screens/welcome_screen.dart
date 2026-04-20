import 'package:flutter/material.dart';
import 'package:gyanshala_app/core/constants/app_strings.dart';

import 'login_screen.dart';
import 'signup_screen.dart';
import 'signup_verification_screen.dart';

class WelcomeScreen extends StatelessWidget {
  final bool showPendingMessage;

  // Add the parameter to the constructor
  const WelcomeScreen({super.key, this.showPendingMessage = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Show this info box only if the user just signed up
                if (showPendingMessage) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          color: Colors.amber.shade800,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Your signup request is sent for admin approval. You will receive a notification once approved.',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Image.network(
                      'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSe_22gfL9zHbi-fK8pMJotQofStQyhuB-fvA&s',
                      height: 100,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.school, size: 50),
                    ),
                    Image.network(
                      'https://scontent.famd4-1.fna.fbcdn.net/v/t39.30808-6/432152915_122100178058257935_5259036002784278436_n.jpg?_nc_cat=106&ccb=1-7&_nc_sid=1d70fc&_nc_ohc=1A-IPcds02oQ7kNvwHPPAAk&_nc_oc=AdpZwBIr0S9wSBypdHGry0UoS8I-XFI36Gfu3HjU31gL9WWkTm2A--l1ch-BNbuEIuo&_nc_zt=23&_nc_ht=scontent.famd4-1.fna&_nc_gid=vwwDhwcUofBF20uKmatx4w&_nc_ss=7a389&oh=00_Af0eK4t7dhM2NlLta1vJQ1c97FMvCs5zoFb-OvvLp9TTAw&oe=69DFE63C',
                      height: 200,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.foundation, size: 50),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                Text(
                  'Student Management System',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SignupScreen()),
                    ),
                    child: const Text(AppStrings.signUp),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: const Text(AppStrings.logIn),
                  ),
                ),
                const SizedBox(height: 16),
                // UPDATED: Check Approval Button
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SignupVerificationScreen(),
                      ),
                    );
                  },
                  child: const Text("Check Signup Status"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
