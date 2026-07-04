import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../theme.dart';
import '../services/ai_service.dart';
import '../app_state.dart';

class TransportVerificationScreen extends StatefulWidget {
  final AppState state;
  const TransportVerificationScreen({super.key, required this.state});

  @override
  State<TransportVerificationScreen> createState() => _TransportVerificationScreenState();
}

class _TransportVerificationScreenState extends State<TransportVerificationScreen> {
  final ImagePicker _picker = ImagePicker();
  
  File? _selfieFile;
  File? _permitFile;
  File? _vehicleFile;
  
  bool _isScanning = false;
  Map<String, dynamic>? _result;

  Future<void> _pickImage(int step) async {
    final source = step == 1 ? ImageSource.camera : ImageSource.gallery;
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    
    if (picked != null) {
      setState(() {
        if (step == 1) _selfieFile = File(picked.path);
        else if (step == 2) _permitFile = File(picked.path);
        else if (step == 3) _vehicleFile = File(picked.path);
      });
    }
  }

  Future<void> _runAIVerification() async {
    if (_selfieFile == null || _permitFile == null || _vehicleFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all 3 photo uploads first.')),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _result = null;
    });

    final res = await NecxaAI.verifyTransportDriver(
      driverSelfie: _selfieFile!,
      permitImage: _permitFile!,
      vehicleImage: _vehicleFile!
    );

    setState(() {
      _isScanning = false;
      _result = res;
    });

    if (res['verified'] == true) {
      // Driver profile was automatically updated by the edge function!
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification Successful! Plate: ${res['number_plate']}'),
          backgroundColor: Colors.green,
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context, true);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification Failed: ${res['error'] ?? "Documents rejected."}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _buildStep(int step, String title, String subtitle, IconData icon, File? file) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: file != null ? C.brand : Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: file != null ? C.brand : Colors.white10,
          child: Icon(file != null ? Icons.check : icon, color: Colors.white),
        ),
        title: Text(title, style: syne(sz: 16, w: FontWeight.w700, c: Colors.white)),
        subtitle: Text(subtitle, style: dm(sz: 13, c: Colors.white60)),
        trailing: file != null 
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(file, width: 60, height: 60, fit: BoxFit.cover)
            )
          : TextButton(
              onPressed: () => _pickImage(step),
              child: Text('Upload', style: dm(c: C.brand)),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Courier Verification', style: syne(sz: 18, w: FontWeight.w700, c: Colors.white)),
      ),
      body: _isScanning
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: C.brand),
                  const SizedBox(height: 24),
                  Text('Necxa AI is scanning documents...', style: syne(sz: 16, c: Colors.white)),
                  const SizedBox(height: 8),
                  Text('Analyzing license plates and permits', style: dm(sz: 13, c: Colors.white54)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Become a Courier', style: syne(sz: 28, w: FontWeight.w900, c: Colors.white)),
                  const SizedBox(height: 8),
                  Text('Submit your documents to get instantly verified by AI and start earning 96% commissions on all deliveries.', style: dm(sz: 15, c: Colors.white70)),
                  const SizedBox(height: 40),
                  
                  _buildStep(1, 'Live Selfie', 'Take a quick photo of your face', Icons.face, _selfieFile),
                  _buildStep(2, 'Driving Permit', 'Scan your official driving license', Icons.badge, _permitFile),
                  _buildStep(3, 'Vehicle License Plate', 'Clear photo of the back plate', Icons.directions_car, _vehicleFile),

                  if (_result != null && _result!['verified'] == false)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: Text('AI Rejection: ${_result!['error'] ?? "Documents did not match requirements."}', style: dm(c: Colors.redAccent)),
                    ),

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: C.brand,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: (_selfieFile != null && _permitFile != null && _vehicleFile != null)
                          ? _runAIVerification
                          : null,
                      child: Text('Run AI Verification', style: syne(sz: 16, w: FontWeight.w800, c: Colors.white)),
                    ),
                  )
                ],
              ),
            ),
    );
  }
}
