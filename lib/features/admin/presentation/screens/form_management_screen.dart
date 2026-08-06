import 'package:flutter/material.dart';
import 'package:gyanshala_app/core/models/user_role.dart';
import 'package:gyanshala_app/core/theme/app_theme.dart';
import 'package:gyanshala_app/features/admin/presentation/screens/form_response_hub.dart';
import 'package:gyanshala_app/features/employees/presentation/screens/form_filler_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'form_builder_canvas.dart';

class FormManagementScreen extends StatefulWidget {
  const FormManagementScreen({super.key});
  @override
  State<FormManagementScreen> createState() => _FormManagementScreenState();
}

class _FormManagementScreenState extends State<FormManagementScreen> {
  List<Map<String, dynamic>> _formsList = [];
  bool _isLoading = false;
  @override
  void initState() {
    super.initState();
    _fetchFormsFromSupabase();
  }

  Future<void> _fetchFormsFromSupabase() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final data = await supabase.from('forms').select('id, title, roles').order('title');
      setState(() {
        _formsList = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error syncing forms collection: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteFormDocument(String formId, String formTitle) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final bool confirmDelete =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.redAccent, size: 28),
                SizedBox(width: 8),
                Text("Delete?", style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              "Are you sure you want to delete \"$formTitle\"?\n\nThis operation will permanently purge all related canvas questions and matching user submission entries.",
              style: const TextStyle(height: 1.4),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Permanently Delete", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmDelete) return;
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('forms').delete().eq('id', formId);
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text("\"$formTitle\" successfully removed from database."), backgroundColor: Colors.green),
      );
      await _fetchFormsFromSupabase();
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text("Failed to destroy form entity row: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _createNewForm() {
    final titleController = TextEditingController();
    final List<UserRole> allRoles = UserRole.values;
    final Set<UserRole> selectedRoles = {...UserRole.values};
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          "Create New Form",
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
        ),
        content: StatefulBuilder(
          builder: (context, setModalState) {
            return SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(hintText: "Enter form title...", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Visible to Roles", style: Theme.of(context).textTheme.titleSmall),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      await _showRoleSelectorDialog(selectedRoles);
                      setModalState(() {});
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "Visible to Roles"),
                      child: Text(
                        selectedRoles.length == UserRole.values.length
                            ? "All Roles"
                            : selectedRoles.map((e) => e.label).join(", "),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
            onPressed: () async {
              final text = titleController.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(dialogContext);
              setState(() => _isLoading = true);
              try {
                final supabase = Supabase.instance.client;
                final newFormRow = await supabase
                    .from('forms')
                    .insert({
                      'title': text,
                      'roles': selectedRoles.length == allRoles.length ? null : selectedRoles.map((e) => e.name).toList(),
                    })
                    .select('id, title, roles')
                    .single();
                await _fetchFormsFromSupabase();
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FormBuilderCanvas(
                      formId: newFormRow['id'].toString(),
                      formTitle: newFormRow['title'],
                      roles: newFormRow['roles'] == null
                          ? UserRole.values.map((e) => e.name).toList()
                          : List<String>.from(newFormRow['roles']),
                    ),
                  ),
                ).then((_) {
                  if (mounted) _fetchFormsFromSupabase();
                });
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Failed to instantiate form database entry: $e"), backgroundColor: Colors.red),
                );
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text("Create Form", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Form Management"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchFormsFromSupabase)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
          : _formsList.isEmpty
          ? const Center(
              child: Text("No forms found", style: TextStyle(color: Colors.grey)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _formsList.length,
              itemBuilder: (context, index) {
                final form = _formsList[index];
                final String currentFormId = form['id'].toString();
                final String currentFormTitle = form['title'] ?? '[no title]';
                return Card(
                  margin: const EdgeInsets.only(bottom: 13),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: ListTile(
                      title: Text(currentFormTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.play_arrow_rounded, color: Colors.orange),
                            tooltip: "Test Fill Form",
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      FormFillerScreen(formId: currentFormId, formTitle: currentFormTitle, isTestMode: true),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.visibility, color: Colors.green),
                            tooltip: "View Form's Responses",
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FormResponseHub(formId: currentFormId, formTitle: currentFormTitle),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            tooltip: "Edit Form Template",
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FormBuilderCanvas(
                                    formId: currentFormId,
                                    formTitle: currentFormTitle,
                                    roles: form['roles'] == null
                                        ? UserRole.values.map((e) => e.name).toList()
                                        : List<String>.from(form['roles']),
                                  ),
                                ),
                              ).then((_) => _fetchFormsFromSupabase());
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            tooltip: "Delete",
                            onPressed: () => _deleteFormDocument(currentFormId, currentFormTitle),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewForm,
        backgroundColor: AppTheme.primaryBlue,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Create Form", style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Future<void> _showRoleSelectorDialog(Set<UserRole> selectedRoles) async {
    final tempSelection = {...selectedRoles};

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Select Visible Roles"),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        value: tempSelection.length == UserRole.values.length,
                        title: const Text("Select All", style: TextStyle(fontWeight: FontWeight.bold)),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              tempSelection
                                ..clear()
                                ..addAll(UserRole.values);
                            } else {
                              tempSelection.clear();
                            }
                          });
                        },
                      ),
                      const Divider(),
                      ...UserRole.values.map(
                        (role) => CheckboxListTile(
                          value: tempSelection.contains(role),
                          title: Text(role.label),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (checked) {
                            setDialogState(() {
                              if (checked == true) {
                                tempSelection.add(role);
                              } else {
                                tempSelection.remove(role);
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () {
                    if (tempSelection.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select at least one role.")));
                      return;
                    }

                    selectedRoles
                      ..clear()
                      ..addAll(tempSelection);

                    Navigator.pop(context);
                  },
                  child: const Text("OK"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Future<void> _showRoleSelectorDialog(Set<UserRole> selectedRoles) async {}
}

// class _showRoleSelectorDialog {
// }

// extension on _FormManagementScreenState {
//   Future<void> _showRoleSelectorDialog(Set<UserRole> selectedRoles) {}
// }

// Future<void> _showRoleSelectorDialog(Set<UserRole> selectedRoles) async {
// }
