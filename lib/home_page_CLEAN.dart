// home_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jeevanlink/chatbot_page.dart';
import 'package:jeevanlink/create_request_page.dart';
import 'package:jeevanlink/login_page.dart';
import 'package:jeevanlink/request_details_page.dart';
import 'package:jeevanlink/settings_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      if (mounted) {
        setState(() {
          _userProfile = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching profile: ${e.toString()}')),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: SpinKitFadingCircle(color: Colors.redAccent)),
      );
    }

    final userRole = _userProfile?['role'];
    final userName = _userProfile?['full_name'] ?? 'User';
    final userPhone = _userProfile?['phone'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          userRole == 'donor' ? 'Donor Dashboard' : 'Requestor Dashboard',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy, size: 28),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChatbotPage()),
              );
            },
            tooltip: 'AI Assistant',
          ),
          if (userRole == 'donor') const NotificationBell(),
        ],
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      drawer: AppDrawer(userName: userName, userPhone: userPhone),
      body: userRole == 'donor'
          ? EnhancedDonorDashboard(userProfile: _userProfile!)
          : EnhancedHospitalDashboard(userProfile: _userProfile!),
      floatingActionButton: userRole == 'hospital'
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CreateRequestPage()),
                );
              },
              icon: const Icon(Icons.add),
              label: Text('New Request', style: GoogleFonts.poppins()),
              backgroundColor: Colors.redAccent,
            )
          : null,
    );
  }
}

class AppDrawer extends StatelessWidget {
  final String userName;
  final String userPhone;

  const AppDrawer({super.key, required this.userName, required this.userPhone});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          UserAccountsDrawerHeader(
            accountName: Text(userName, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            accountEmail: Text(userPhone, style: GoogleFonts.poppins()),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                userName.isNotEmpty ? userName[0] : 'U',
                style: const TextStyle(fontSize: 40.0, color: Colors.redAccent),
              ),
            ),
            decoration: const BoxDecoration(color: Colors.red),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: Text('Dashboard', style: GoogleFonts.poppins()),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text('History', style: GoogleFonts.poppins()),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text('Settings', style: GoogleFonts.poppins()),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text('Logout', style: GoogleFonts.poppins()),
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  _NotificationBellState createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _notificationCount = 0;
  StreamSubscription? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    final userId = Supabase.instance.client.auth.currentUser!.id;

    _notificationSubscription = Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .listen((notifications) {
      if (mounted) {
        final filteredNotifications = notifications.where((notification) => 
          notification['donor_id'] == userId && notification['status'] == 'pending'
        ).toList();
        
        setState(() {
          _notificationCount = filteredNotifications.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none, size: 28),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Notifications page coming soon!')),
            );
          },
        ),
        if (_notificationCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12)
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                '$_notificationCount',
                style: const TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class EnhancedDonorDashboard extends StatefulWidget {
  final Map<String, dynamic> userProfile;
  const EnhancedDonorDashboard({super.key, required this.userProfile});

  @override
  State<EnhancedDonorDashboard> createState() => _EnhancedDonorDashboardState();
}

class _EnhancedDonorDashboardState extends State<EnhancedDonorDashboard> {
  StreamSubscription<Position>? _positionStreamSubscription;
  String? _currentlyTrackingResponseId;
  List<Map<String, dynamic>> _notifications = [];
  StreamSubscription? _notificationStream;
  
  // Dashboard stats
  int _totalDonations = 0;
  int _pendingRequests = 0;
  DateTime? _lastDonation;

  @override
  void initState() {
    super.initState();
    _loadDashboardStats();
    _loadInitialNotifications();
    _setupNotificationStream();
  }

  Future<void> _loadDashboardStats() async {
    try {
      final userId = widget.userProfile['id'];
      
      // Get total donations (accepted responses)
      final donationsData = await Supabase.instance.client
          .from('donor_responses')
          .select('created_at')
          .eq('donor_id', userId)
          .eq('response_status', 'accepted');
      
      // Get last donation date
      DateTime? lastDonationDate;
      if (donationsData.isNotEmpty) {
        final dates = donationsData.map((d) => DateTime.parse(d['created_at'])).toList();
        dates.sort((a, b) => b.compareTo(a));
        lastDonationDate = dates.first;
      }

      if (mounted) {
        setState(() {
          _totalDonations = donationsData.length;
          _lastDonation = lastDonationDate;
        });
      }
    } catch (e) {
      print('Error loading dashboard stats: $e');
    }
  }

  Future<void> _loadInitialNotifications() async {
    try {
      final data = await Supabase.instance.client
          .from('notifications')
          .select()
          .eq('donor_id', widget.userProfile['id'])
          .eq('status', 'pending');
      
      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(data);
          _pendingRequests = data.length;
        });
      }
    } catch (e) {
      print('Error loading notifications: $e');
    }
  }

  void _setupNotificationStream() {
    _notificationStream = Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .listen((allNotifications) {
      if (mounted) {
        final filtered = allNotifications.where((n) => 
          n['donor_id'] == widget.userProfile['id'] && n['status'] == 'pending'
        ).toList();
        
        setState(() {
          _notifications = filtered;
          _pendingRequests = filtered.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _notificationStream?.cancel();
    super.dispose();
  }

  Future<void> _acceptRequest(BuildContext context, String requestId, String notificationId) async {
    final donorId = Supabase.instance.client.auth.currentUser!.id;
    try {
      final response = await Supabase.instance.client
          .from('donor_responses')
          .insert({
            'request_id': requestId,
            'donor_id': donorId,
            'response_status': 'accepted',
          })
          .select()
          .single();

      await Supabase.instance.client
          .from('notifications')
          .update({'status': 'accepted'})
          .eq('id', int.parse(notificationId));

      await Supabase.instance.client.from('donor_tracking').insert({
        'response_id': response['id'],
        'donor_id': donorId,
        'request_id': requestId,
      });

      _loadDashboardStats();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you! You can now start sharing your location.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _startLiveTracking(String responseId) async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
        return;
      }
    }

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10
      ),
    ).listen((position) async {
      await Supabase.instance.client.from('donor_tracking').update({
        'current_lat': position.latitude,
        'current_lon': position.longitude,
        'last_updated': DateTime.now().toIso8601String(),
      }).eq('response_id', responseId);
    });

    setState(() {
      _currentlyTrackingResponseId = responseId;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Live location sharing has started!'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _stopLiveTracking() {
    _positionStreamSubscription?.cancel();
    setState(() {
      _currentlyTrackingResponseId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Live location sharing has stopped.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Widget _buildStatsCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: GoogleFonts.poppins(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Section
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.redAccent,
                    child: Text(
                      widget.userProfile['blood_type'] ?? 'O+',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back, ${widget.userProfile['full_name'] ?? 'Donor'}!',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Ready to save lives today?',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          Text(
            'Your Impact',
            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          
          Row(
            children: [
              Expanded(
                child: _buildStatsCard(
                  'Total\nDonations',
                  _totalDonations.toString(),
                  Icons.favorite,
                  Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatsCard(
                  'Pending\nRequests',
                  _pendingRequests.toString(),
                  Icons.pending_actions,
                  Colors.orange,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.blue, size: 32),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last Donation',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _lastDonation != null 
                          ? DateFormat.yMMMd().format(_lastDonation!)
                          : 'No donations yet',
                        style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          Text(
            'Active Requests',
            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          
          if (_notifications.isEmpty)
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Icon(Icons.shield, size: 80, color: Colors.green[300]),
                    const SizedBox(height: 16),
                    Text(
                      'All Clear!',
                      style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'No active requests. Thank you for being a hero!',
                      style: GoogleFonts.poppins(),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notification = _notifications[index];
                final requestId = notification['request_id'];
                final notificationId = notification['id'].toString();

                return FutureBuilder(
                  future: Supabase.instance.client
                      .from('blood_requests')
                      .select('*, hospital:requesting_hospital_id(*)')
                      .eq('id', requestId)
                      .single(),
                  builder: (context, requestSnapshot) {
                    if (!requestSnapshot.hasData) {
                      return const Card(
                        child: SizedBox(
                          height: 150,
                          child: Center(child: SpinKitFadingCircle(color: Colors.redAccent)),
                        ),
                      );
                    }

                    final request = requestSnapshot.data!;
                    final hospitalName = request['hospital']?['hospital_name'] ?? 'A Hospital';
                    final status = notification['status'];

                    return Card(
                      elevation: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.redAccent,
                                  child: Text(
                                    request['blood_type'],
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Urgent Request',
                                        style: GoogleFonts.poppins(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        hospitalName,
                                        style: GoogleFonts.poppins(color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            Text(
                              'Units Required: ${request['units_required'] ?? 1}',
                              style: GoogleFonts.poppins(),
                            ),
                            const SizedBox(height: 16),
                            if (status == 'pending')
                              Center(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.favorite),
                                  label: Text('I Can Donate', style: GoogleFonts.poppins()),
                                  onPressed: () => _acceptRequest(context, requestId, notificationId),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                ),
                              )
                            else if (status == 'accepted')
                              Center(
                                child: _currentlyTrackingResponseId != null
                                    ? ElevatedButton.icon(
                                        icon: const Icon(Icons.stop_circle_outlined),
                                        label: Text('Stop Sharing Location', style: GoogleFonts.poppins()),
                                        onPressed: _stopLiveTracking,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                        ),
                                      )
                                    : FutureBuilder(
                                        future: _getResponseId(requestId),
                                        builder: (context, responseSnapshot) {
                                          final responseId = responseSnapshot.data;
                                          return ElevatedButton.icon(
                                            icon: const Icon(Icons.my_location),
                                            label: Text('Start Live Tracking', style: GoogleFonts.poppins()),
                                            onPressed: responseId != null 
                                              ? () => _startLiveTracking(responseId) 
                                              : null,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.blue,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  Future<String?> _getResponseId(String requestId) async {
    try {
      final response = await Supabase.instance.client
          .from('donor_responses')
          .select('id')
          .eq('request_id', requestId)
          .eq('donor_id', widget.userProfile['id'])
          .eq('response_status', 'accepted')
          .single();
      return response['id'];
    } catch (e) {
      return null;
    }
  }
}

class EnhancedHospitalDashboard extends StatefulWidget {
  final Map<String, dynamic> userProfile;
  const EnhancedHospitalDashboard({super.key, required this.userProfile});

  @override
  State<EnhancedHospitalDashboard> createState() => _EnhancedHospitalDashboardState();
}

class _EnhancedHospitalDashboardState extends State<EnhancedHospitalDashboard> {
  List<Map<String, dynamic>> _requests = [];
  StreamSubscription? _requestsSubscription;
  
  int _totalRequests = 0;
  int _activeRequests = 0;
  int _fulfilledRequests = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardStats();
    _listenToRequests();
  }

  @override
  void dispose() {
    _requestsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboardStats() async {
    try {
      final hospitalId = widget.userProfile['id'];
      
      final allRequests = await Supabase.instance.client
          .from('blood_requests')
          .select('status')
          .eq('requesting_hospital_id', hospitalId);

      int total = allRequests.length;
      int active = allRequests.where((r) => r['status'] == 'active').length;
      int fulfilled = allRequests.where((r) => r['status'] == 'fulfilled').length;

      if (mounted) {
        setState(() {
          _totalRequests = total;
          _activeRequests = active;
          _fulfilledRequests = fulfilled;
        });
      }
    } catch (e) {
      print('Error loading dashboard stats: $e');
    }
  }

  void _listenToRequests() async {
    final hospitalId = widget.userProfile['id'];
    
    try {
      final initialRequests = await Supabase.instance.client
          .from('blood_requests')
          .select()
          .eq('requesting_hospital_id', hospitalId)
          .order('created_at', ascending: false);
      
      setState(() {
        _requests = initialRequests;
      });
    } catch (e) {
      print('Error loading initial requests: $e');
    }

    _requestsSubscription = Supabase.instance.client
        .from('blood_requests')
        .stream(primaryKey: ['id'])
        .listen((data) {
      if (mounted) {
        final filteredRequests = data.where((request) => 
          request['requesting_hospital_id'] == hospitalId
        ).toList();
        
        filteredRequests.sort((a, b) => 
          DateTime.parse(b['created_at']).compareTo(DateTime.parse(a['created_at']))
        );
        
        setState(() {
          _requests = filteredRequests;
        });
        
        _loadDashboardStats();
      }
    });
  }

  Widget _buildStatsCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: GoogleFonts.poppins(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.blue,
                    child: Text(
                      widget.userProfile['hospital_name']?.substring(0, 1) ?? 'H',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.userProfile['hospital_name'] ?? 'Hospital',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Managing blood requests efficiently',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          Text(
            'Hospital Statistics',
            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          
          Row(
            children: [
              Expanded(
                child: _buildStatsCard(
                  'Total\nRequests',
                  _totalRequests.toString(),
                  Icons.list_alt,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatsCard(
                  'Active\nRequests',
                  _activeRequests.toString(),
                  Icons.pending,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatsCard(
                  'Fulfilled\nRequests',
                  _fulfilledRequests.toString(),
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          Text(
            'Quick Actions',
            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          
          Row(
            children: [
              Expanded(
                child: Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CreateRequestPage()),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Icon(Icons.add_circle, size: 40, color: Colors.red),
                          const SizedBox(height: 8),
                          Text(
                            'New Request',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Emergency feature coming soon!')),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Icon(Icons.emergency, size: 40, color: Colors.red),
                          const SizedBox(height: 8),
                          Text(
                            'Emergency',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Requests',
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All requests page coming soon!')),
                  );
                },
                child: Text('View All', style: GoogleFonts.poppins()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          if (_requests.isEmpty)
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Icon(Icons.add_circle_outline, size: 80, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(
                      'No Active Requests',
                      style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Click the "+" button to post a new blood request.',
                      style: GoogleFonts.poppins(),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _requests.take(5).length,
              itemBuilder: (context, index) {
                final request = _requests[index];
                final isUrgent = DateTime.now().difference(
                  DateTime.parse(request['created_at'])
                ).inHours < 2;
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.red,
                          child: Text(
                            request['blood_type'],
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (isUrgent)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Text(
                      '${request['units_required'] ?? 1} Units of ${request['blood_type']}',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Posted ${_getTimeAgo(DateTime.parse(request['created_at']))}',
                          style: GoogleFonts.poppins(fontSize: 12),
                        ),
                        if (isUrgent)
                          Text(
                            'URGENT',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FutureBuilder<int>(
                          future: _getDonorCount(request['id']),
                          builder: (context, snapshot) {
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${snapshot.data ?? 0}',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                Text(
                                  'Donors',
                                  style: GoogleFonts.poppins(fontSize: 10),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RequestDetailsPage(requestId: request['id']),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  Future<int> _getDonorCount(String requestId) async {
    try {
      final data = await Supabase.instance.client
          .from('donor_responses')
          .select('id')
          .eq('request_id', requestId)
          .eq('response_status', 'accepted');
      return data.length;
    } catch (e) {
      return 0;
    }
  }
}