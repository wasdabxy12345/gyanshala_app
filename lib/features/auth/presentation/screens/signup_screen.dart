import 'package:dropdown_search/dropdown_search.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/models/location_model.dart';
import 'package:gyanshala_app/core/models/user_role.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/login_screen.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/welcome_screen.dart';
import 'package:gyanshala_app/features/location/controller/location_controller.dart' as controller;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/validators.dart';
import '../widgets/auth_shell.dart';
import '../widgets/role_selector.dart';

class AppConfig {
  static const bool useDevBypass = false;
}

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _qualificationController = TextEditingController();
  UserRole _selectedRole = UserRole.shikshaMitra38;
  String? _selectedGender;

  final List<LocationItem> _clusters = [];
  final List<LocationItem> _villages = [];
  final List<LocationItem> _schools = [];
  String? _selectedClusterId;
  String? _selectedVillageId;

  final List<String> _selectedSchoolIds = [];
  final List<LocationItem> _selectedSchoolObjects = [];

  @override
  void initState() {
    super.initState();
    _loadClusters();
  }

  Future<void> _loadClusters() async {
    try {
      final clusters = await controller.fetchClusters();
      setState(() {
        _clusters.clear();
        _clusters.addAll(clusters);
      });
    } catch (e) {
      debugPrint('Error loading clusters: $e');
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _qualificationController.dispose();
    super.dispose();
  }

  Future<void> _onSignupPressed() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      String? pushToken = await FirebaseMessaging.instance.getToken();
      await ref
          .read(authRepositoryProvider)
          .signup(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            identifier: _phoneController.text.trim(),
            password: _passwordController.text,
            role: _selectedRole.name,
            gender: _selectedGender,
            pushToken: pushToken,
            qualification: _qualificationController.text.trim(),
            schoolIds: _selectedSchoolIds,
          );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_id', _phoneController.text.trim());

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const WelcomeScreen(showPendingMessage: true)),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNotAdmin =
        _selectedRole == UserRole.shikshaMitra38 ||
        _selectedRole == UserRole.shikshaMitra910 ||
        _selectedRole == UserRole.mentorBV8;
    final isMultiSchool = _selectedRole == UserRole.mentorBV8;

    return AuthShell(
      title: 'Signup',
      subtitle: 'Submit details for admin approval',
      formChild: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Position *', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            RoleSelector(
              selectedRole: _selectedRole,
              onRoleSelected: (role) => setState(() {
                _selectedRole = role;
                _selectedSchoolIds.clear();
                _selectedSchoolObjects.clear();
                _selectedClusterId = null;
                _selectedVillageId = null;
              }),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstNameController,
                    decoration: const InputDecoration(labelText: 'First Name *', prefixIcon: Icon(Icons.person_outline)),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lastNameController,
                    decoration: const InputDecoration(labelText: 'Last Name *'),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _selectedGender,
              decoration: const InputDecoration(
                labelText: 'Gender *',
                prefixIcon: Icon(Icons.wc_outlined),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Male', child: Text('Male')),
                DropdownMenuItem(value: 'Female', child: Text('Female')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (value) => setState(() => _selectedGender = value),
              validator: (value) => (value == null || value.isEmpty) ? 'Gender Selection Required' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number *', prefixIcon: Icon(Icons.phone_outlined)),
              validator: (value) {
                final phone = value?.trim() ?? '';
                if (phone.isEmpty) return 'Required';
                if (!Validators.isValidPhone(phone)) return 'Invalid phone';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password *', prefixIcon: Icon(Icons.lock_outline)),
              validator: (value) => (value == null || value.length < 6) ? 'Min 6 characters' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm Password *', prefixIcon: Icon(Icons.lock_person_outlined)),
              validator: (value) => (value != _passwordController.text) ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 14),
            if (isNotAdmin) ...[
              TextFormField(
                controller: _qualificationController,
                decoration: const InputDecoration(labelText: 'Qualification *', prefixIcon: Icon(Icons.school_outlined)),
                validator: (value) => (value == null || value.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),

              DropdownSearch<LocationItem>(
                items: (filter, infiniteScrollProps) => _clusters,
                itemAsString: (item) => item.name,
                compareFn: (item1, item2) => item1.id == item2.id,
                decoratorProps: const DropDownDecoratorProps(
                  decoration: InputDecoration(labelText: "🏢 Select Cluster *", border: OutlineInputBorder()),
                ),
                onSelected: (data) async {
                  setState(() {
                    _selectedClusterId = data?.id;
                    _selectedVillageId = null;
                    if (!isMultiSchool) {
                      _selectedSchoolIds.clear();
                      _selectedSchoolObjects.clear();
                    }
                    _villages.clear();
                    _schools.clear();
                  });
                  if (data != null) {
                    final list = await controller.fetchVillages(data.id);
                    setState(() => _villages.addAll(list));
                  }
                },
              ),

              const SizedBox(height: 14),

              DropdownSearch<LocationItem>(
                enabled: _selectedClusterId != null,
                items: (filter, loadProps) => _villages,
                itemAsString: (item) => item.name,
                compareFn: (item1, item2) => item1.id == item2.id,
                decoratorProps: DropDownDecoratorProps(
                  decoration: InputDecoration(
                    labelText: "🏡 Select Village *",
                    border: const OutlineInputBorder(),
                    filled: _selectedClusterId == null,
                    fillColor: Colors.grey.shade100,
                  ),
                ),
                onSelected: (data) async {
                  setState(() {
                    _selectedVillageId = data?.id;
                    if (!isMultiSchool) {
                      _selectedSchoolIds.clear();
                      _selectedSchoolObjects.clear();
                    }
                    _schools.clear();
                  });
                  if (data != null) {
                    final list = await controller.fetchSchools(data.id);
                    setState(() => _schools.addAll(list));
                  }
                },
              ),

              const SizedBox(height: 14),

              if (isMultiSchool) ...[
                DropdownSearch<LocationItem>(
                  enabled: _selectedVillageId != null,
                  items: (filter, loadProps) => _schools,
                  itemAsString: (item) => item.name,
                  compareFn: (item1, item2) => item1.id == item2.id,
                  decoratorProps: DropDownDecoratorProps(
                    decoration: InputDecoration(
                      labelText: "🏫 Select School *",
                      border: const OutlineInputBorder(),
                      filled: _selectedVillageId == null,
                      fillColor: Colors.grey.shade100,
                    ),
                  ),
                  popupProps: PopupProps.menu(
                    itemBuilder: (context, item, isDisabled, isSelected) {
                      final isAdded = _selectedSchoolIds.contains(item.id);
                      return ListTile(
                        title: Text(item.name),
                        trailing: TextButton.icon(
                          onPressed: isAdded
                              ? null
                              : () {
                                  setState(() {
                                    _selectedSchoolIds.add(item.id);
                                    _selectedSchoolObjects.add(item);
                                  });
                                  Navigator.of(context).pop();
                                },
                          icon: Icon(isAdded ? Icons.check : Icons.add, size: 16),
                          label: Text(isAdded ? 'Added' : 'Add'),
                        ),
                      );
                    },
                  ),
                  onSelected: (data) {
                    if (data != null && !_selectedSchoolIds.contains(data.id)) {
                      setState(() {
                        _selectedSchoolIds.add(data.id);
                        _selectedSchoolObjects.add(data);
                      });
                    }
                  },
                ),

                if (_selectedSchoolObjects.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      '🎒 Selected Schools *',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _selectedSchoolObjects.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final school = _selectedSchoolObjects[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.school, color: Colors.blue),
                          title: Text(school.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                            onPressed: () => setState(() {
                              _selectedSchoolIds.remove(school.id);
                              _selectedSchoolObjects.removeAt(index);
                            }),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                FormField<List<String>>(
                  initialValue: _selectedSchoolIds,
                  validator: (_) => _selectedSchoolIds.isEmpty ? 'Please pick at least one school before continuing.' : null,
                  builder: (state) => state.hasError
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8, left: 12),
                          child: Text(state.errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                        )
                      : const SizedBox.shrink(),
                ),
              ] else ...[
                DropdownSearch<LocationItem>(
                  enabled: _selectedVillageId != null,
                  items: (filter, loadProps) => _schools,
                  itemAsString: (item) => item.name,
                  compareFn: (item1, item2) => item1.id == item2.id,
                  decoratorProps: DropDownDecoratorProps(
                    decoration: InputDecoration(
                      labelText: "Select School *",
                      border: const OutlineInputBorder(),
                      filled: _selectedVillageId == null,
                      fillColor: Colors.grey.shade100,
                    ),
                  ),
                  onSelected: (data) {
                    setState(() {
                      _selectedSchoolIds.clear();
                      if (data != null) _selectedSchoolIds.add(data.id);
                    });
                  },
                  validator: (value) => (value == null || _selectedSchoolIds.isEmpty) ? 'School Selection Required' : null,
                ),
              ],
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _onSignupPressed, child: const Text('Signup')),
            ),
          ],
        ),
      ),
      footer: _buildFooter(),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Already have an account? '),
        TextButton(
          onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen())),
          child: const Text('Log In'),
        ),
      ],
    );
  }
}
