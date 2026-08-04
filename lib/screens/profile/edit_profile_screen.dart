import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/profile_photo_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() =>
      _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();
  final ProfilePhotoService _photoService =
  ProfilePhotoService();

  File? _selectedPhoto;
  String? _photoUrl;

  bool _isUploadingPhoto = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;

    _nameController.text = user?.displayName ?? '';
    _photoUrl = user?.photoURL;
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    final name = _nameController.text.trim();

    setState(() {
      _isLoading = true;
    });

    try {
      await user.updateDisplayName(name);
      await user.reload();

      final refreshedUser = FirebaseAuth.instance.currentUser;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(
        {
          'uid': user.uid,
          'name': name,
          'email': user.email?.trim().toLowerCase() ?? '',
          'photoUrl': refreshedUser?.photoURL ?? _photoUrl ?? '',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message ?? 'Unable to update profile.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to update profile: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _chooseProfilePhoto() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1600,
      );

      if (image == null) {
        return;
      }

      final cropped = await ImageCropper().cropImage(
        sourcePath: image.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop profile photo',
            lockAspectRatio: true,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
            ],
          ),
          IOSUiSettings(
            title: 'Crop profile photo',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );

      if (cropped == null || !mounted) {
        return;
      }

      setState(() {
        _selectedPhoto = File(cropped.path);
      });
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to choose photo: $error',
          ),
        ),
      );
    }
  }

  Future<void> _uploadSelectedPhoto() async {
    final photo = _selectedPhoto;

    if (photo == null) {
      return;
    }

    setState(() {
      _isUploadingPhoto = true;
    });

    try {
      final url =
      await _photoService.uploadProfilePhoto(photo);

      if (!mounted) return;

      setState(() {
        _photoUrl = url;
        _selectedPhoto = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo updated.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to upload photo: $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
      }
    }
  }

  ImageProvider? _profileImageProvider() {
    if (_selectedPhoto != null) {
      return FileImage(_selectedPhoto!);
    }

    if (_photoUrl != null && _photoUrl!.trim().isNotEmpty) {
      return NetworkImage(_photoUrl!);
    }

    return null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final imageProvider = _profileImageProvider();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 52,
                        backgroundColor:
                        Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        backgroundImage: imageProvider,
                        child: imageProvider == null
                            ? Text(
                          _nameController.text
                              .trim()
                              .isEmpty
                              ? '?'
                              : _nameController.text
                              .trim()[0]
                              .toUpperCase(),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                            fontWeight:
                            FontWeight.bold,
                          ),
                        )
                            : null,
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: IconButton.filled(
                          tooltip: 'Choose photo',
                          onPressed: _isUploadingPhoto
                              ? null
                              : _chooseProfilePhoto,
                          icon: const Icon(
                            Icons.camera_alt_outlined,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_selectedPhoto != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isUploadingPhoto
                        ? null
                        : _uploadSelectedPhoto,
                    icon: _isUploadingPhoto
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                        : const Icon(
                      Icons.cloud_upload_outlined,
                    ),
                    label: const Text('Upload Photo'),
                  ),
                ],
                const SizedBox(height: 28),
                TextFormField(
                  controller: _nameController,
                  enabled:
                  !_isLoading && !_isUploadingPhoto,
                  textCapitalization:
                  TextCapitalization.words,
                  textInputAction:
                  TextInputAction.done,
                  onChanged: (_) {
                    setState(() {});
                  },
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    prefixIcon:
                    Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    final name = value?.trim() ?? '';

                    if (name.isEmpty) {
                      return 'Enter your name';
                    }

                    if (name.length < 2) {
                      return 'Name must contain at least 2 characters';
                    }

                    return null;
                  },
                  onFieldSubmitted: (_) {
                    if (!_isLoading &&
                        !_isUploadingPhoto) {
                      _saveProfile();
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: user?.email ?? '',
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon:
                    Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed:
                  _isLoading || _isUploadingPhoto
                      ? null
                      : _saveProfile,
                  child: _isLoading
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Text('Save Profile'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}