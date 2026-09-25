import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:lab_05/data/models/paper.dart';
import 'package:lab_05/data/services/figure_export.dart';
import 'package:lab_05/ui/core/snackbar.dart';

/// Saves one figure wherever the person picks in the native Save As dialog.
///
/// The file name is worked out before the first `await`, so it always names
/// the figure that was asked for, whatever the screen shows by the time the
/// dialog closes.
Future<void> saveFigureAs(
  BuildContext context, {
  required PaperFigure figure,
  required String paperTitle,
}) async {
  final suggestedName = FigureExporter.fileNameFor(paperTitle, figure);

  final Uint8List bytes;
  try {
    bytes = await File(figure.path).readAsBytes();
  } catch (e) {
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Could not read the figure file: $e',
        isError: true,
      );
    }
    return;
  }

  try {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Export figure image',
      fileName: suggestedName,
      bytes: bytes,
    );
    if (saved != null && context.mounted) {
      showAppSnackBar(context, 'Saved $suggestedName', isSuccess: true);
    }
  } catch (e) {
    if (context.mounted) {
      showAppSnackBar(context, 'Could not save the image: $e', isError: true);
    }
  }
}

/// Asks for a folder and writes every figure of the paper into it, with a
/// `figures.json` describing them.
Future<void> exportAllFigures(
  BuildContext context, {
  required FigureExporter exporter,
  required String collectionId,
  required PaperDocument paper,
}) async {
  final String? targetPath;
  try {
    targetPath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose a folder for the exported figures',
    );
  } catch (e) {
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Could not open the folder picker: $e',
        isError: true,
      );
    }
    return;
  }
  if (targetPath == null) return;

  try {
    final result = await exporter.exportAll(
      collectionId: collectionId,
      paper: paper,
      target: Directory(targetPath),
    );
    if (!context.mounted) return;
    if (result.exported == 0) {
      showAppSnackBar(
        context,
        'No figure images were found on disk, so nothing was exported. '
        'Re-import the paper to extract its figures again.',
        isError: true,
      );
      return;
    }
    final missing = result.skipped == 0
        ? ''
        : ' (${_count(result.skipped, 'figure')} missing on disk skipped)';
    showAppSnackBar(
      context,
      'Exported ${_count(result.exported, 'figure')} '
      'to ${result.directory}$missing',
      isSuccess: true,
      duration: const Duration(seconds: 5),
    );
  } catch (e) {
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Could not export the figures: $e',
        isError: true,
      );
    }
  }
}

/// "1 figure", "3 figures".
String _count(int n, String noun) => '$n ${n == 1 ? noun : '${noun}s'}';
