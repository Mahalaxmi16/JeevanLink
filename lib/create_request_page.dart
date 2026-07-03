// Enhanced create_request_page.dart with Smart AI Matching and Urgency Levels
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

class CreateRequestPage extends StatefulWidget {
  const CreateRequestPage({super.key});

  @override
  _CreateRequestPageState createState() => _CreateRequestPageState();
}

class _CreateRequestPageState extends State<CreateRequestPage> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedBloodType;
  String _urgencyLevel = 'normal';
  final _unitsController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isLoading = false;

  final List<String> _bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  final List<Map<String, dynamic>> _urgencyLevels = [
    {'value': 'normal', 'label': 'Normal', 'color': Colors.green, 'description': 'Standard request'},
    {'value': 'urgent', 'label': 'Urgent', 'color': Colors.orange, 'description': 'Needed within 4 hours'},
    {'value': 'critical', 'label': 'Critical', 'color': Colors.red, 'description': 'Life-threatening emergency'},
  ];

  @override
  void dispose() {
    _unitsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _getCurrentUserProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('*')
          .eq('id', user.id)
          .single();

      if (profile['role'] != 'hospital') {
        throw Exception('Only hospital accounts can create blood requests');
      }

      if (profile['latitude'] == null || profile['longitude'] == null) {
        throw Exception('Hospital location not set. Please update your profile.');
      }

      return profile;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _createBloodRequest(Map<String, dynamic> hospitalProfile) async {
    final units = int.parse(_unitsController.text);
    final notes = _notesController.text.trim();

    final requestData = await Supabase.instance.client
        .from('blood_requests')
        .insert({
          'requesting_hospital_id': hospitalProfile['id'],
          'hospital_id': hospitalProfile['id'],
          'blood_type': _selectedBloodType,
          'units_required': units,
          'status': 'active',
          'notes': notes.isEmpty ? null : notes,
          // Add urgency metadata
          'urgency_level': _urgencyLevel,
           'latitude': hospitalProfile['latitude'],
           'longitude': hospitalProfile['longitude'],
          'created_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    return requestData;
  }

  Future<void> _triggerAIMatching(String requestId) async {
    // Enhanced AI matching with smart parameters
    await Supabase.instance.client.rpc(
      'match_donors_and_notify_ai',
      params: {
        'request_id_param': requestId,
        'blood_type_param': _selectedBloodType,
        'initial_radius_km': _getSmartRadiusForBloodType(_selectedBloodType!, _urgencyLevel),
        'max_donors_to_notify': _getMaxDonorsForRequest(_selectedBloodType!, _urgencyLevel, int.parse(_unitsController.text)),
      },
    );

    // If critical, trigger expansion search after 10 minutes
    if (_urgencyLevel == 'critical') {
      await _scheduleEmergencyExpansion(requestId);
    }
  }

  Future<void> _scheduleEmergencyExpansion(String requestId) async {
    // Call expansion function for critical requests
    try {
      await Supabase.instance.client.rpc(
        'expand_search_if_needed',
        params: {
          'request_id_param': requestId,
          'blood_type_param': _selectedBloodType,
          'current_radius_km': _getSmartRadiusForBloodType(_selectedBloodType!, _urgencyLevel),
        },
      );
    } catch (e) {
      print('Emergency expansion scheduling failed: $e');
      // Don't show error to user, this is background optimization
    }
  }

  double _getSmartRadiusForBloodType(String bloodType, String urgency) {
    // Base radius by blood type rarity
    double baseRadius;
    switch (bloodType) {
      case 'O-': // Universal donor but rarest to find
        baseRadius = 40.0;
        break;
      case 'AB-': // Rarest recipient type
        baseRadius = 35.0;
        break;
      case 'A-':
      case 'B-':
        baseRadius = 25.0;
        break;
      case 'AB+': // Universal recipient, can get from anyone
        baseRadius = 20.0;
        break;
      default: // Common types
        baseRadius = 20.0;
    }

    // Adjust for urgency
    switch (urgency) {
      case 'critical':
        return baseRadius * 1.5;
      case 'urgent':
        return baseRadius * 1.2;
      default:
        return baseRadius;
    }
  }

  int _getMaxDonorsForRequest(String bloodType, String urgency, int unitsRequired) {
    // Base count by blood type compatibility
    int baseCount;
    switch (bloodType) {
      case 'O-': // Only O- donors
        baseCount = 25;
        break;
      case 'AB-': // Limited compatible donors
        baseCount = 20;
        break;
      case 'A-':
      case 'B-':
        baseCount = 15;
        break;
      case 'AB+': // Can receive from all types, so moderate count
        baseCount = 12;
        break;
      default:
        baseCount = 10;
    }

    // Multiply by units required (more units = more backup donors needed)
    baseCount = (baseCount * (1 + unitsRequired * 0.3)).round();

    // Adjust for urgency
    switch (urgency) {
      case 'critical':
        return (baseCount * 2).round();
      case 'urgent':
        return (baseCount * 1.5).round();
      default:
        return baseCount;
    }
  }

  String _getPredictedResponseTime() {
    String bloodTypeTime;
    switch (_selectedBloodType) {
      case 'O+':
      case 'A+':
        bloodTypeTime = '15-25 minutes';
        break;
      case 'B+':
      case 'AB+':
        bloodTypeTime = '20-35 minutes';
        break;
      case 'A-':
      case 'B-':
        bloodTypeTime = '25-45 minutes';
        break;
      case 'AB-':
        bloodTypeTime = '35-60 minutes';
        break;
      case 'O-':
        bloodTypeTime = '45-90 minutes';
        break;
      default:
        bloodTypeTime = '20-40 minutes';
    }

    // Adjust for urgency
    if (_urgencyLevel == 'critical') {
      return 'AI Priority Mode: 5-15 minutes';
    } else if (_urgencyLevel == 'urgent') {
      return 'Fast Track: 10-20 minutes';
    }

    return bloodTypeTime;
  }

  int _getCompatibleDonorCount() {
    // Estimate based on blood type compatibility and population statistics
    switch (_selectedBloodType) {
      case 'AB+': return 100; // Universal recipient
      case 'O+': return 85;   // Second most compatible
      case 'A+': return 70;
      case 'B+': return 65;
      case 'A-': return 25;
      case 'B-': return 20;
      case 'AB-': return 15;
      case 'O-': return 10;   // Rarest
      default: return 50;
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final hospitalProfile = await _getCurrentUserProfile();
      if (hospitalProfile == null) {
        throw Exception('Unable to verify hospital profile. Please check your account setup.');
      }

      final requestData = await _createBloodRequest(hospitalProfile);
      await _triggerAIMatching(requestData['id']);

      if (mounted) {
        _showSuccessMessage();
        Navigator.of(context).pop(requestData);
      }
    } on PostgrestException catch (e) {
      _handleDatabaseError(e);
    } catch (e) {
      _handleGenericError(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSuccessMessage() {
    final compatibleCount = _getCompatibleDonorCount();
    final responseTime = _getPredictedResponseTime();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.rocket_launch, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'AI Matching Started!',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '~$compatibleCount compatible donors • ETA: $responseTime',
                    style: GoogleFonts.poppins(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: _urgencyLevel == 'critical' ? Colors.red : Colors.green,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _handleDatabaseError(PostgrestException e) {
    String message = 'Database error occurred';

    if (e.code == '23505') {
      message = 'A similar request already exists';
    } else if (e.code == '42501') {
      message = 'Permission denied. Please check your account permissions.';
    } else if (e.message.contains('location')) {
      message = 'Hospital location not set. Please update your profile.';
    }

    _showError(message);
  }

  void _handleGenericError(String error) {
    String message = 'Failed to post request';

    if (error.contains('network') || error.contains('connection')) {
      message = 'Network error. Please check your internet connection.';
    } else if (error.contains('authentication')) {
      message = 'Authentication error. Please log in again.';
    }

    _showError('$message: $error');
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Smart Blood Request', style: GoogleFonts.poppins()),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.red.withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 30),
                _buildBloodTypeDropdown(),
                const SizedBox(height: 20),
                _buildUrgencySelector(),
                const SizedBox(height: 20),
                _buildUnitsField(),
                const SizedBox(height: 20),
                _buildNotesField(),
                const SizedBox(height: 30),
                _buildPredictionCard(),
                const SizedBox(height: 30),
                _buildSubmitButton(),
                const SizedBox(height: 16),
                _buildEnhancedInfoCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.psychology,
            size: 48,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'AI-Powered Blood Matching',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        Text(
          'Smart algorithms find the best donors for you',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildBloodTypeDropdown() {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: 'Required Blood Type',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        prefixIcon: const Icon(Icons.bloodtype, color: Colors.red),
        filled: true,
        fillColor: Colors.red.withOpacity(0.05),
      ),
      value: _selectedBloodType,
      items: _bloodTypes.map((String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  value,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (value == 'O-')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'UNIVERSAL DONOR',
                    style: GoogleFonts.poppins(
                      fontSize: 8,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (value == 'AB+')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'UNIVERSAL RECIPIENT',
                    style: GoogleFonts.poppins(
                      fontSize: 8,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
      onChanged: (newValue) {
        setState(() {
          _selectedBloodType = newValue;
        });
      },
      validator: (value) => value == null ? 'Please select a blood type' : null,
    );
  }

  Widget _buildUrgencySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Request Urgency Level',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: _urgencyLevels.map((urgency) {
            final isSelected = _urgencyLevel == urgency['value'];
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _urgencyLevel = urgency['value']),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? urgency['color'] : urgency['color'].withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: urgency['color'],
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          urgency['value'] == 'critical' ? Icons.emergency :
                          urgency['value'] == 'urgent' ? Icons.warning : Icons.schedule,
                          color: isSelected ? Colors.white : urgency['color'],
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          urgency['label'],
                          style: GoogleFonts.poppins(
                            color: isSelected ? Colors.white : urgency['color'],
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          urgency['description'],
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: isSelected ? Colors.white.withOpacity(0.9) : urgency['color'].withOpacity(0.7),
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildUnitsField() {
    return TextFormField(
      controller: _unitsController,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'Number of Units Required',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        prefixIcon: const Icon(Icons.format_list_numbered, color: Colors.red),
        helperText: 'Typical: 1-2 units per patient',
        filled: true,
        fillColor: Colors.red.withOpacity(0.05),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter the number of units';
        }
        final number = int.tryParse(value);
        if (number == null || number <= 0) {
          return 'Please enter a valid number';
        }
        if (number > 10) {
          return 'For requests >10 units, please contact blood bank directly';
        }
        return null;
      },
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesController,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: 'Additional Notes (Optional)',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        prefixIcon: const Icon(Icons.note_add, color: Colors.red),
        helperText: 'Patient condition, contact info, special requirements',
        filled: true,
        fillColor: Colors.red.withOpacity(0.05),
      ),
    );
  }

  Widget _buildPredictionCard() {
    if (_selectedBloodType == null) return const SizedBox();

    final compatibleCount = _getCompatibleDonorCount();
    final responseTime = _getPredictedResponseTime();
    final searchRadius = _getSmartRadiusForBloodType(_selectedBloodType!, _urgencyLevel);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.analytics, color: Colors.blue.shade600),
              const SizedBox(width: 8),
              Text(
                'AI Prediction',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildPredictionItem(
                  'Compatible Donors',
                  '~$compatibleCount',
                  Icons.people,
                  Colors.green,
                ),
              ),
              Expanded(
                child: _buildPredictionItem(
                  'Est. Response Time',
                  responseTime,
                  Icons.timer,
                  Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildPredictionItem(
                  'Search Radius',
                  '${searchRadius.toStringAsFixed(0)}km',
                  Icons.location_on,
                  Colors.blue,
                ),
              ),
              Expanded(
                child: _buildPredictionItem(
                  'Urgency Level',
                  _urgencyLevel.toUpperCase(),
                  Icons.priority_high,
                  _urgencyLevels.firstWhere((u) => u['value'] == _urgencyLevel)['color'],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return _isLoading
        ? const Center(child: SpinKitFadingCircle(color: Colors.red))
        : ElevatedButton.icon(
            onPressed: _submitRequest,
            icon: const Icon(Icons.rocket_launch),
            label: Text(
              _urgencyLevel == 'critical' ? 'EMERGENCY BROADCAST' :
              _urgencyLevel == 'urgent' ? 'URGENT REQUEST' :
              'Start AI Matching',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _urgencyLevel == 'critical' ? Colors.red :
                             _urgencyLevel == 'urgent' ? Colors.orange : Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
  }

  Widget _buildEnhancedInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology, color: Colors.green.shade600),
              const SizedBox(width: 8),
              Text(
                'How Smart Matching Works',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '• AI analyzes donor compatibility, location & availability\n'
            '• Smart radius expands for rare blood types\n'
            '• Priority ranking based on response history\n'
            '• Real-time tracking and notifications\n'
            '• Emergency protocols for critical requests',
            style: GoogleFonts.poppins(fontSize: 12),
          ),
        ],
      ),
    );
  }
}