import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

Future<File> convertMp4ToMp3(File input, File output) async {
  final session = await FFmpegKit.executeWithArguments([
    '-y', '-i', input.path, '-vn', '-codec:a', 'libmp3lame', '-q:a', '2', output.path,
  ]);
  final returnCode = await session.getReturnCode();
  if (!ReturnCode.isSuccess(returnCode) || !await output.exists() || await output.length() == 0) {
    final logs = await session.getOutput();
    throw StateError(logs?.trim().isNotEmpty == true ? logs! : 'MP3 conversion failed.');
  }
  return output;
}
