import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/providers/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> initialData;
  const EditProfileScreen({super.key, required this.initialData});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _roleController;
  late TextEditingController _qualificationController;
  late TextEditingController _phoneController;
  late TextEditingController _villageController;
  late TextEditingController _clusterController;
  late TextEditingController _schoolController;
  late TextEditingController _otpController;

  bool _isLoading = false;
  bool _isOtpSent = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _firstNameController = TextEditingController(text: d['first_name']);
    _lastNameController = TextEditingController(text: d['last_name']);
    _roleController = TextEditingController(text: d['role']);
    _qualificationController = TextEditingController(text: d['qualification']);
    _phoneController = TextEditingController(text: d['phone']);
    _villageController = TextEditingController(text: d['village']);
    _clusterController = TextEditingController(text: d['cluster']);
    _schoolController = TextEditingController(text: d['school']);
    _otpController = TextEditingController();
  }

  @override
  void dispose() {
    for (var controller in [
      _firstNameController,
      _lastNameController,
      _roleController,
      _qualificationController,
      _phoneController,
      _villageController,
      _clusterController,
      _schoolController,
      _otpController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() => _isLoading = true);
    try {
      // await ref.read(authRepositoryProvider).updateProfile(
      //   firstName: _firstNameController.text.trim(),
      //   lastName: _lastNameController.text.trim(),
      //   qualification: _qualificationController.text.trim(),
      //   village: _villageController.text.trim(),
      //   cluster: _clusterController.text.trim(),
      //   school: _schoolController.text.trim(),
      // );

      final newPhone = _phoneController.text.trim();
      final oldPhone = widget.initialData['phone'];

      if (newPhone != oldPhone) {
        // await ref.read(supabaseClientProvider).auth.updateUser(UserAttributes(phone: newPhone));
        setState(() => _isOtpSent = true);
      } else {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyPhoneUpdate() async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(supabaseClientProvider)
          .auth
          .verifyOTP(
            phone: _phoneController.text.trim(),
            token: _otpController.text.trim(),
            type: OtpType.phoneChange,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Invalid OTP: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildTextField("First Name", _firstNameController, enabled: false),
            _buildTextField("Last Name", _lastNameController, enabled: false),
            _buildTextField("Role", _roleController, enabled: false),
            const Divider(height: 32),
            _buildTextField(
              "Phone (Authentication)",
              _phoneController,
              isNumber: true,
            ),

            if (_isOtpSent) ...[
              const SizedBox(height: 8),
              _buildTextField("Enter OTP", _otpController, isNumber: true),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : (_isOtpSent ? _verifyPhoneUpdate : _handleSave),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isOtpSent ? "Verify & Save" : "Update Profile"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool enabled = true,
    bool isNumber = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: isNumber ? TextInputType.phone : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          filled: !enabled,
          fillColor: enabled ? null : Colors.grey[200],
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
