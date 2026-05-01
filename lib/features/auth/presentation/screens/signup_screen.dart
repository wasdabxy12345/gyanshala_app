import 'package:dropdown_search/dropdown_search.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/core/models/location_model.dart';
import 'package:gyanshala_app/core/models/user_model.dart';
import 'package:gyanshala_app/core/providers/auth_provider.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/welcome_screen.dart';
import 'package:gyanshala_app/features/location/controller/location_controller.dart'
    as controller;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/validators.dart';
import '../widgets/auth_shell.dart';
import '../widgets/role_selector.dart';
import 'login_screen.dart';

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
  // final _authRepository = AuthRepositoryImpl.instance;
  UserRole _selectedRole = UserRole.mentor;

  final List<LocationItem> _clusters = [];
  final List<LocationItem> _villages = [];
  final List<LocationItem> _schools = [];

  String? _selectedClusterId;
  String? _selectedVillageId;
  String? _selectedSchoolId;

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
            role: _selectedRole.label,
            pushToken: pushToken,
          );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_id', _phoneController.text.trim());

      debugPrint('Signup successful and ID persisted.');

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const WelcomeScreen(showPendingMessage: true),
        ),
        (route) => false,
      );
    } catch (e) {
      debugPrint('--- SIGNUP ERROR ---');
      debugPrint(e.toString());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Signup',
      subtitle: 'Submit details for admin approval',
      formChild: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Text(
              'Select Position *',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            RoleSelector(
              selectedRole: _selectedRole,
              onRoleSelected: (role) {
                setState(() => _selectedRole = role);
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'First Name *',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lastNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Last Name *'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Phone Number *',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (value) {
                final phone = value?.trim() ?? '';
                if (phone.isEmpty) {
                  return 'Phone Number is required';
                }
                if (!Validators.isValidPhone(phone)) {
                  return 'Enter a valid phone number';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Password *',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Password is required';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm Password *',
                prefixIcon: Icon(Icons.lock_person_outlined),
              ),
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
            if (_selectedRole != UserRole.admin) ...[
              DropdownSearch<LocationItem>(
                compareFn: (item, selectedItem) => item.id == selectedItem.id,
                popupProps: PopupProps.menu(
                  showSearchBox: true,
                  searchFieldProps: TextFieldProps(
                    decoration: InputDecoration(
                      hintText: "Search Cluster...",
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                  emptyBuilder: (context, searchEntry) =>
                      const Center(child: Text("No clusters found")),
                ),
                items: (filter, loadProps) => _clusters,
                itemAsString: (LocationItem u) => u.name,
                decoratorProps: DropDownDecoratorProps(
                  decoration: InputDecoration(
                    labelText: "Select Cluster *",
                    border: OutlineInputBorder(),
                  ),
                ),
                selectedItem: _clusters.isEmpty || _selectedClusterId == null
                    ? null
                    : _clusters.firstWhere(
                        (c) => c.id == _selectedClusterId,
                        orElse: () => LocationItem(id: '', name: ''),
                      ),
                onChanged: (LocationItem? data) async {
                  if (data == null) return;
                  setState(() {
                    _selectedClusterId = data.id;
                    _selectedVillageId = null;
                    _selectedSchoolId = null;
                    _villages.clear();
                    _schools.clear();
                  });
                  final list = await controller.fetchVillages(data.id);
                  setState(() {
                    _villages.addAll(list);
                  });
                },
              ),

              if (_selectedClusterId != null) ...[
                const SizedBox(height: 14),
                DropdownSearch<LocationItem>(
                  compareFn: (item, selectedItem) => item.id == selectedItem.id,
                  popupProps: PopupProps.menu(
                    showSearchBox: true,
                    searchFieldProps: TextFieldProps(
                      decoration: InputDecoration(
                        hintText: "Search Village...",
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                    emptyBuilder: (context, searchEntry) =>
                        const Center(child: Text("No villages found")),
                  ),
                  items: (filter, loadProps) => _villages,
                  itemAsString: (LocationItem u) => u.name,
                  decoratorProps: const DropDownDecoratorProps(
                    decoration: InputDecoration(
                      labelText: "Select Village *",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  selectedItem: _villages.isEmpty || _selectedVillageId == null
                      ? null
                      : _villages.firstWhere(
                          (v) => v.id == _selectedVillageId,
                          orElse: () => LocationItem(id: '', name: ''),
                        ),
                  onChanged: (LocationItem? data) async {
                    if (data == null) return;
                    setState(() {
                      _selectedVillageId = data.id;
                      _selectedSchoolId = null;
                      _schools.clear();
                    });
                    final list = await controller.fetchSchools(data.id);
                    setState(() {
                      _schools.addAll(list);
                    });
                  },
                ),
              ],

              if (_selectedVillageId != null) ...[
                const SizedBox(height: 14),
                DropdownSearch<LocationItem>(
                  compareFn: (item, selectedItem) => item.id == selectedItem.id,
                  popupProps: PopupProps.menu(
                    showSearchBox: true,
                    searchFieldProps: TextFieldProps(
                      decoration: InputDecoration(
                        hintText: "Search School...",
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                    emptyBuilder: (context, searchEntry) =>
                        const Center(child: Text("No schools found")),
                  ),
                  items: (filter, loadProps) => _schools,
                  itemAsString: (LocationItem u) => u.name,
                  decoratorProps: const DropDownDecoratorProps(
                    decoration: InputDecoration(
                      labelText: "Select School *",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  selectedItem: _schools.isEmpty || _selectedSchoolId == null
                      ? null
                      : _schools.firstWhere(
                          (s) => s.id == _selectedSchoolId,
                          orElse: () => LocationItem(id: '', name: ''),
                        ),
                  onChanged: (LocationItem? data) {
                    setState(() {
                      _selectedSchoolId = data?.id;
                    });
                  },
                ),
              ],
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _onSignupPressed,
                child: const Text('Signup'),
              ),
            ),
          ],
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Already have an account? '),
          TextButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('Log In'),
          ),
        ],
      ),
    );
  }
}
