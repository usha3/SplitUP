import 'package:flutter/material.dart';

class ReceiptViewerScreen extends StatelessWidget {
  final String receiptUrl;

  const ReceiptViewerScreen({
    super.key,
    required this.receiptUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Center(
          child: Image.network(
            receiptUrl,
            fit: BoxFit.contain,
            loadingBuilder: (
                context,
                child,
                loadingProgress,
                ) {
              if (loadingProgress == null) {
                return child;
              }

              return const Center(
                child: CircularProgressIndicator(),
              );
            },
            errorBuilder: (
                context,
                error,
                stackTrace,
                ) {
              return const Center(
                child: Column(
                  mainAxisAlignment:
                  MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.broken_image_outlined,
                      size: 70,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Unable to load receipt',
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}