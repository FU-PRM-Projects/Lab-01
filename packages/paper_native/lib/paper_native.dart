import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'src/rust/frb_generated.dart';

export 'src/rust/api/pdf_parser.dart';
export 'src/rust/api/vector_index.dart';

Future<void> initializeNative({String? libraryPath}) => RustLib.init(
  externalLibrary: libraryPath == null
      ? null
      : ExternalLibrary.open(libraryPath),
);
