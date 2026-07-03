import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:jeevanlink/request_details_page.dart';

class AllRequestsPage extends StatefulWidget {
  const AllRequestsPage({super.key});

  @override
  State<AllRequestsPage> createState() => _AllRequestsPageState();
}

class _AllRequestsPageState extends State<AllRequestsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  String? _selectedBloodType;
  final List<String> _bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'All Requests',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _selectedBloodType = value == 'All' ? null : value;
              });
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem<String>(
                  value: 'All',
                  child: Text('All Types'),
                ),
                ..._bloodTypes.map((type) => PopupMenuItem<String>(
                  value: type,
                  child: Text(type),
                )),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_selectedBloodType != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Chip(
                label: Text('Type: $_selectedBloodType'),
                onDeleted: () {
                  setState(() {
                    _selectedBloodType = null;
                  });
                },
                deleteIcon: const Icon(Icons.close, size: 18),
              ),
            ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase
                  .from('blood_requests')
                  .stream(primaryKey: ['id'])
                  .order('created_at', ascending: false),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: SpinKitFadingCircle(color: Colors.redAccent));
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.list_alt, size: 80, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'No active requests found',
                          style: GoogleFonts.poppins(fontSize: 18, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                // Filter locally for now since stream doesn't support complex filtering easily
                // Also filter for 'active' status
                final requests = snapshot.data!.where((r) {
                  final matchesType = _selectedBloodType == null || r['blood_type'] == _selectedBloodType;
                  final isActive = r['status'] == 'active';
                  return matchesType && isActive;
                }).toList();

                if (requests.isEmpty) {
                  return Center(
                    child: Text(
                      'No requests match your filter',
                      style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];
                    final isUrgent = DateTime.now().difference(DateTime.parse(request['created_at'])).inHours < 2;

                    return Card(
                      elevation: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RequestDetailsPage(requestId: request['id']),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 25,
                                backgroundColor: Colors.redAccent,
                                child: Text(
                                  request['blood_type'],
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '${request['units_required']} Units Required',
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (isUrgent) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'URGENT',
                                              style: GoogleFonts.poppins(
                                                fontSize: 10,
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    FutureBuilder(
                                      future: _getHospitalName(request['requesting_hospital_id']),
                                      builder: (context, snapshot) {
                                        return Text(
                                          snapshot.data ?? 'Loading hospital...',
                                          style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 14),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _getHospitalName(String hospitalId) async {
    try {
      final data = await _supabase
          .from('profiles')
          .select('hospital_name')
          .eq('id', hospitalId)
          .single();
      return data['hospital_name'] ?? 'Unknown Hospital';
    } catch (e) {
      return 'Unknown Hospital';
    }
  }
}
