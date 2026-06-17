// lib/screens/report_animal_screen.dart
//
// MODIFIED FILE – ML integration only.
// All original functionality preserved.
// New additions:
//   • MLService initialised in initState / disposed in dispose
//   • _runPrediction() called after image selection
//   • PredictionWidget rendered below the photo picker
//   • animalPrediction, predictionConfidence, predictionTimestamp saved to Firestore

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ml/prediction_result.dart';
import '../ml/prediction_widget.dart';
import '../services/ml_service.dart';
import '../theme/app_theme.dart';

class ReportAnimalScreen extends StatefulWidget {
  const ReportAnimalScreen({super.key});

  @override
  State<ReportAnimalScreen> createState() => _ReportAnimalScreenState();
}

class _ReportAnimalScreenState extends State<ReportAnimalScreen> {
  // ── Form state (unchanged) ────────────────────────────────────────────────
  final _formKey            = GlobalKey<FormState>();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _animalType;
  String? _healthStatus;

  bool _imageSelected = false;
  bool _submitted     = false;
  bool _loading       = false;

  XFile?     _selectedImage;
  Uint8List? _imageBytes;
  String?    _imageBase64;

  static const _types = ['Cat', 'Dog', 'Unknown'];
  static const _statuses = [
    'Healthy',
    'Needs Feeding',
    'Injured',
    'Sick',
    'Unknown',
  ];

  // ── ML state (new) ────────────────────────────────────────────────────────
  final _ml               = MLService();
  bool              _mlLoading  = false;
  PredictionResult? _prediction;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Pre-load the TFLite interpreter so the first classification is fast.
    _ml.initialize();
  }

  @override
  void dispose() {
    _locationController.dispose();
    _descriptionController.dispose();
    _ml.dispose();
    super.dispose();
  }

  // ── Image picking + ML (modified) ─────────────────────────────────────────

  Future<void> _pickImage() async {
    final picker = ImagePicker();

    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 15,
      maxWidth: 400,
    );

    if (pickedFile == null) return;

    final bytes       = await pickedFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    if (base64Image.length > 900000) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Image is too large. Please choose another image.')),
      );
      return;
    }

    setState(() {
      _selectedImage = pickedFile;
      _imageBytes    = bytes;
      _imageBase64   = base64Image;
      _imageSelected = true;
      // Reset previous prediction
      _prediction  = null;
      _mlLoading   = true;
    });

    // ── Run ML inference ──
    await _runPrediction(bytes);
  }

  /// Classifies [imageBytes] and updates [_prediction].
  Future<void> _runPrediction(Uint8List imageBytes) async {
    try {
      final result = await _ml.classify(imageBytes);
      if (!mounted) return;
      setState(() {
        _prediction = result;
        _mlLoading  = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _prediction = PredictionResult.error('Unable to identify the animal.');
        _mlLoading  = false;
      });
    }
  }

  // ── Clear (unchanged logic + reset ML state) ──────────────────────────────

  void _clear() {
    _formKey.currentState?.reset();
    _locationController.clear();
    _descriptionController.clear();

    setState(() {
      _animalType    = null;
      _healthStatus  = null;
      _imageSelected = false;
      _selectedImage = null;
      _imageBytes    = null;
      _imageBase64   = null;
      _submitted     = false;
      _loading       = false;
      // ML state
      _prediction    = null;
      _mlLoading     = false;
    });
  }

  // ── Submit (original + ML fields saved to Firestore) ──────────────────────

  Future<void> _submit() async {
    setState(() => _submitted = true);

    final formValid = _formKey.currentState!.validate();

    if (!formValid || _imageBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please complete all fields and upload an image')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) throw Exception('User is not logged in');

      print('CURRENT USER UID: ${user.uid}');

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      print('USER EXISTS: ${userDoc.exists}');

      // Build the Firestore document – original fields + new ML fields
      await FirebaseFirestore.instance.collection('reports').add({
        // ── Original fields (unchanged) ──
        'animalType':   _animalType,
        'healthStatus': _healthStatus,
        'location':     _locationController.text.trim(),
        'description':  _descriptionController.text.trim(),
        'imageBase64':  _imageBase64,
        'imageName':    _selectedImage?.name,
        'status':       'Pending',
        'userId':       user.uid,
        'createdAt':    FieldValue.serverTimestamp(),
        // ── New ML fields ──
        'animalPrediction':    _prediction?.success == true
            ? _prediction!.label
            : 'Unknown',
        'predictionConfidence': _prediction?.success == true
            ? _prediction!.confidence
            : 0.0,
        'predictionTimestamp': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'reportsCount':   FieldValue.increment(1),
        'volunteerScore': FieldValue.increment(5),
      });

      if (!mounted) return;
      Navigator.pushNamed(context, '/success');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit report: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Validation helper (unchanged) ─────────────────────────────────────────

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'This field is required';
    return null;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showImageError = _submitted && !_imageSelected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Animal'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _clear,
            child: const Text('Clear',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ── Photo label (unchanged) ──────────────────────────────────
              Text(
                'Animal Photo *',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.text.withValues(alpha: 0.72),
                    ),
              ),

              const SizedBox(height: 8),

              // ── Photo picker (unchanged) ─────────────────────────────────
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _loading ? null : _pickImage,
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: showImageError
                          ? AppTheme.error
                          : AppTheme.border,
                      width: showImageError ? 1.8 : 1.2,
                    ),
                  ),
                  child: _imageBytes == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt,
                                size: 42, color: AppTheme.primary),
                            const SizedBox(height: 10),
                            Text(
                              'Tap to Upload Photo',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: AppTheme.primary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Image will be saved in Firestore for Sprint 2',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppTheme.text
                                        .withValues(alpha: 0.48),
                                  ),
                            ),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.memory(
                            _imageBytes!,
                            width: double.infinity,
                            height: 160,
                            fit: BoxFit.cover,
                          ),
                        ),
                ),
              ),

              if (showImageError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Animal photo is required before submitting',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),

              // ── ML Prediction widget (NEW – inserted right after photo) ──
              PredictionWidget(
                isLoading: _mlLoading,
                result:    _prediction,
              ),

              const SizedBox(height: 18),

              // ── Animal Type dropdown (unchanged) ─────────────────────────
              DropdownButtonFormField<String>(
                initialValue: _animalType,
                decoration: const InputDecoration(
                  labelText: 'Animal Type',
                  prefixIcon: Icon(Icons.pets),
                ),
                items: _types
                    .map((type) =>
                        DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
                onChanged: _loading
                    ? null
                    : (value) => setState(() => _animalType = value),
                validator: _required,
              ),

              const SizedBox(height: 14),

              // ── Location field (unchanged) ───────────────────────────────
              TextFormField(
                controller: _locationController,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Location Found',
                  hintText: 'e.g. N28 Engineering Block, UTM',
                  prefixIcon: Icon(Icons.location_on),
                ),
                validator: _required,
              ),

              const SizedBox(height: 14),

              // ── Description field (unchanged) ────────────────────────────
              TextFormField(
                controller: _descriptionController,
                enabled: !_loading,
                maxLength: 300,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText:
                      'Describe the animal condition, appearance, and behavior.',
                  prefixIcon: Icon(Icons.notes),
                  alignLabelWithHint: true,
                ),
                validator: _required,
              ),

              const SizedBox(height: 4),

              // ── Health Status dropdown (unchanged) ───────────────────────
              DropdownButtonFormField<String>(
                initialValue: _healthStatus,
                decoration: const InputDecoration(
                  labelText: 'Health Status',
                  prefixIcon: Icon(Icons.health_and_safety),
                ),
                items: _statuses
                    .map((status) =>
                        DropdownMenuItem(value: status, child: Text(status)))
                    .toList(),
                onChanged: _loading
                    ? null
                    : (value) => setState(() => _healthStatus = value),
                validator: _required,
              ),

              const SizedBox(height: 18),

              // ── Info banner (unchanged) ──────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.16)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppTheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your report will be reviewed by UTM animal welfare volunteers.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.text.withValues(alpha: 0.68),
                              height: 1.45,
                            ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // ── Submit button (unchanged) ────────────────────────────────
              ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_loading ? 'Submitting...' : 'Submit Report'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
