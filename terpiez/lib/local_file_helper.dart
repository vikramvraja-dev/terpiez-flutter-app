import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

class LocalFileHelper {

  static Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  // Saves Terpie details  local JSON file
  static Future<void> saveTerpieData(String id, Map<String, dynamic> data) async {
    final path = await _localPath;
    final file = File('$path/terpie_$id.json');
    await file.writeAsString(jsonEncode(data));
  }

  static Future<Map<String, dynamic>?> getTerpieData(String id) async {
    try {
      final path = await _localPath;
      final file = File('$path/terpie_$id.json');
      if (await file.exists()) {
        final contents = await file.readAsString();
        return jsonDecode(contents);
      }
    } catch (e) {
      print("Error reading Terpie info: $e");
    }
    return null;
  }

  static Future<void> saveTerpieImage(String id, String base64String, {bool isThumb = false}) async {
    final path = await _localPath;
    final suffix = isThumb ? '_thumb' : '';
    final file = File('$path/terpie_img_$id$suffix.png');
    
    final bytes = base64Decode(base64String);
    await file.writeAsBytes(bytes);
  }

  // Retrieves the image 
  static Future<File?> getTerpieImageFile(String id, {bool isThumb = false}) async {
    final path = await _localPath;
    final suffix = isThumb ? '_thumb' : '';
    final file = File('$path/terpie_img_$id$suffix.png');
    if (await file.exists()) {
      return file;
    }
    return null;
  }
}