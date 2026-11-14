import 'dart:ui' as ui;
import 'dart:typed_data';

import '../src/rust/api/starfield.dart' as rust;

/// One 4 KiB Rust parameter atlas, shared by all routes for the app lifetime.
abstract final class AuroraStarfield {
  static const width = 32;
  static const height = 32;
  static ui.Image? _atlas;
  static ui.FragmentProgram? _program;
  static Future<void>? _preparation;
  static ui.Image? get atlas => _atlas;
  static ui.FragmentProgram? get program => _program;

  static Future<void> initialize({required int seed}) =>
      _preparation ??= _load(seed);

  static Future<void> _load(int seed) async {
    final resources = await Future.wait<Object>([
      rust.createStarfield(seed: seed),
      ui.FragmentProgram.fromAsset('shaders/aurora_stars.frag'),
    ]);
    _atlas = await decode(resources[0] as Uint8List);
    _program = resources[1] as ui.FragmentProgram;
  }

  static Future<ui.Image> decode(Uint8List bytes) async {
    if (bytes.length != width * height * 4) {
      throw const FormatException('Invalid starfield atlas size');
    }
    for (var i = 3; i < bytes.length; i += 4) {
      if (bytes[i] != 255) {
        throw const FormatException(
          'Starfield parameter texels must be opaque',
        );
      }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        rowBytes: width * 4,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      codec = await descriptor.instantiateCodec();
      return (await codec.getNextFrame()).image;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
