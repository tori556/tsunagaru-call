import 'dart:io';
import 'package:flutter/material.dart';

class ImageViewerScreen extends StatelessWidget {
  final String? imageUrl;
  final String? localPath;

  const ImageViewerScreen({
    super.key,
    this.imageUrl,
    this.localPath,
  });

  @override
  Widget build(BuildContext context) {
    Widget imgWidget;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      imgWidget = Image.network(imageUrl!, fit: BoxFit.contain);
    } else if (localPath != null && localPath!.isNotEmpty) {
      imgWidget = Image.file(File(localPath!), fit: BoxFit.contain);
    } else {
      imgWidget = const Icon(Icons.broken_image, color: Colors.white, size: 64);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('写真'),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4.0,
          child: imgWidget,
        ),
      ),
    );
  }
}
