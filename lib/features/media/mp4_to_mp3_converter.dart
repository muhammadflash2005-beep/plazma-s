import 'dart:io';
import 'mp4_to_mp3_converter_stub.dart'
    if (dart.library.io) 'mp4_to_mp3_converter_io.dart' as implementation;

Future<File> convertMp4ToMp3(File input, File output) =>
    implementation.convertMp4ToMp3(input, output);
