import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../providers/auth_provider.dart';
import '../../config/api_config.dart';
import '../../widgets/admin_side_navigation.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({Key? key}) : super(key: key);

  @override
  _UserManagementScreenState createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController(); // Added for last name
  // Removed: _selectedRole, _selectedDepartment, _selectedPosition
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose(); // Dispose last name controller
    super.dispose();
  }

  Future<void> _loadUsers({bool showErrors = true}) async {
    setState(() {
      _isLoading = true;
      if (showErrors) _error = null;
    });

    print('Attempting to load users...');

    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      print('Auth Token: $token');

      if (token == null || token.isEmpty) {
        print('Authentication token is missing or empty.');
        setState(() {
          _error = 'Authentication token is missing.';
          _isLoading = false;
        });
        return;
      }

      final url = '${ApiConfig.baseUrl}/auth/users';
      print('Requesting users from: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $token',
        },
      );

      print('Response Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final List<dynamic>? usersJson = responseData['users'] as List<dynamic>?;
        if (usersJson != null) {
          setState(() {
            _users = usersJson.cast<Map<String, dynamic>>();
            _isLoading = false;
          });
        } else {
          if (showErrors) {
            setState(() {
              _error = 'Invalid response format: users array not found';
              _isLoading = false;
            });
          } else {
            setState(() {
              _isLoading = false;
            });
          }
        }
        print('Users loaded successfully: ${_users.length} users');
      } else if (response.statusCode == 401) {
        setState(() {
          _error = 'Failed to load users: Unauthorized access. Please log in again.';
          _isLoading = false;
        });
        // Navigate to login screen
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      } else {
        print('Failed to load users. Status: ${response.statusCode}, Body: ${response.body}');
        if (showErrors) {
          setState(() {
            _error = 'Failed to load users: ${response.statusCode} ${response.body}';
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e, stackTrace) {
      print('Error loading users: $e');
      print('Stack trace: $stackTrace');
      if (showErrors) {
        setState(() {
          _error = 'Failed to load users: $e';
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/auth/register'), // Ensure this endpoint doesn't require role, department, position or can handle their absence
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${authProvider.token}',
        },
        body: json.encode({
          'email': _emailController.text,
          'password': _passwordController.text,
          'firstName': _firstNameController.text, // Changed 'name' to 'firstName'
          'lastName': _lastNameController.text, // Added 'lastName'
          // Removed: 'role': _selectedRole, 'department': _selectedDepartment, 'position': _selectedPosition,
        }),
      );

      if (!mounted) return;
      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User created successfully')),
        );
        _formKey.currentState!.reset();
        _emailController.clear();
        _passwordController.clear();
        _firstNameController.clear();
        _lastNameController.clear(); // Clear last name controller
        // Clear any previous errors before reloading users
        setState(() {
          _error = null;
        });
        await _loadUsers(showErrors: false);
      } else {
        setState(() {
          _error = data['message'] ?? 'Failed to create user';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Network error occurred';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleUserStatus(String userId, bool currentStatus) async {
    if (!mounted) return;
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/auth/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${authProvider.token}',
        },
        body: json.encode({'isActive': !currentStatus}),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        _loadUsers();
      } else {
        final data = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Failed to update user status'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Network error occurred')));
    }
  }

  Future<void> _deleteUser(String userId) async {
    if (!mounted) return;

    // Show confirmation dialog
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: const Text('Are you sure you want to delete this user? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirmed == null || !confirmed) {
      return; // User cancelled the dialog
    }

    setState(() {
      _isLoading = true; // Show loading indicator
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/auth/users/$userId'), // Assuming this is the delete endpoint
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${authProvider.token}',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 204) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User deleted successfully')),
        );
        _loadUsers(); // Refresh the user list
      } else {
        final data = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Failed to delete user: ${response.statusCode}'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error occurred while deleting user')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false; // Hide loading indicator
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Management')),
      drawer: const AdminSideNavigation(currentRoute: '/user_management'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child:
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _emailController,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter an email';
                                    }
                                    if (!value.contains('@')) {
                                      return 'Please enter a valid email';
                                    }
                                    return null;
                                  },
                                ),
                                TextFormField(
                                  controller: _passwordController,
                                  decoration: const InputDecoration(
                                    labelText: 'Password',
                                  ),
                                  obscureText: true,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter a password';
                                    }
                                    if (value.length < 6) {
                                      return 'Password must be at least 6 characters';
                                    }
                                    return null;
                                  },
                                ),
                                TextFormField(
                                  controller: _firstNameController, // Changed to _firstNameController
                                  decoration: const InputDecoration(
                                    labelText: 'First Name', // Changed label to 'First Name'
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter a first name';
                                    }
                                    return null;
                                  },
                                ),
                                TextFormField( // Added TextFormField for Last Name
                                  controller: _lastNameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Last Name',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter a last name'; // Corrected validation message
                                    }
                                    return null;
                                  },
                                ),
                                // Removed DropdownButtonFormField for Role, Department, and Position
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _isLoading ? null : _createUser,
                                  child: const Text('Create User'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'User List',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _users.length,
                                itemBuilder: (context, index) {
                                  final user = _users[index];
                                  return ListTile(
                                    title: Text(user['name'] ?? ''),
                                    subtitle: Text(user['email'] ?? ''),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Removed: Text(user['role'] ?? ''),
                                        // Removed: const SizedBox(width: 8),
                                        Switch(
                                          value: user['isActive'] ?? false,
                                          onChanged: (value) =>
                                              _toggleUserStatus(
                                            user['_id'],
                                            user['isActive'],
                                          ),
                                        ),
                                        const SizedBox(width: 8), // Added spacing
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                          onPressed: () => _deleteUser(user['_id']),
                                          tooltip: 'Delete User',
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
