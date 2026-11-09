import 'package:flutter/material.dart';
import 'package:terpiez/main.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:terpiez/local_file_helper.dart';
import 'dart:convert';

class UserState extends ChangeNotifier {
  int totalTerpiezFound = 0;
  int get totalTerpiez => totalTerpiezFound;
  String userID = "Loading";
  DateTime startDate = DateTime.now();
  List<Map<String, dynamic>> terpiezLocations = [];
  List<LatLng> caughtLocations = [];
  List<String> terpiezCaught = [];

  bool _soundEnabled = true;
  bool get soundEnabled => _soundEnabled;

  /* final List<LatLng> terpiezLocations = [
    const LatLng(38.9869, -76.9426), // McKeldin
    const LatLng(38.9905, -76.9355), // Paint Branch
    const LatLng(38.9902, -76.9471), //Secu stadium
  ];*/

  UserState() {
    _init();
  }
  Future<void> _init() async {
    await _loadUserData();
    await loadServerLocations();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    totalTerpiezFound = prefs.getInt('totalTerpiezFound') ?? 0;

    _soundEnabled = prefs.getBool('soundEnabled') ?? true;

    List<String> savedCaught = prefs.getStringList('terpiezCaught') ?? [];
    terpiezCaught = List<String>.from(savedCaught);

    List<String> savedStringLocations =
        prefs.getStringList('caughtLocations') ?? [];

    caughtLocations = savedStringLocations.map((str)
    {
      List<String> parts = str.split(',');
      return LatLng(double.parse(parts[0]), double.parse(parts[1]));
    }
    ).toList();

    String firstRun = prefs.getString('firstRun') ?? '';
    String storedID = prefs.getString('userID') ?? '';

    if (storedID.isEmpty) {
      storedID = generateUUID();
      await prefs.setString('userID', storedID);
    }
    userID = storedID;

    if (firstRun.isEmpty) {
      firstRun = startDate.toIso8601String();
      await prefs.setString('firstRun', firstRun);
    } else {
      startDate = DateTime.parse(firstRun);
    }

    notifyListeners();
  }

Future<void> loadServerLocations() async {
    List<Map<String, dynamic>> fetchedLocations =
        await RedisHelper.fetchAllLocations();
    terpiezLocations = List<Map<String, dynamic>>.from(fetchedLocations);

    terpiezLocations.removeWhere((terpie) {
      String terpieId = terpie['id'].toString().trim();
      double lat = (terpie['lat'] as num).toDouble();
      double lon = (terpie['lon'] as num).toDouble();

      bool isLocationCaught = caughtLocations.any(
        (caught) => caught.latitude == lat && caught.longitude == lon
      );

      return terpiezCaught.contains(terpieId) && isLocationCaught;
    });

    _syncLocationsToBackground();
    notifyListeners();
  }

  Future<void> _syncLocationsToBackground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('terpiez_locations', jsonEncode(terpiezLocations));
  }

  void updateLocations(List<Map<String, dynamic>> newLocations) {
    terpiezLocations = newLocations;
    _syncLocationsToBackground(); 
    notifyListeners();
  }

  Future<void> toggleSound(bool value) async {
    _soundEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('soundEnabled', value);
    notifyListeners();
  }

  Future<void> clearData() async {
    final prefs = await SharedPreferences.getInstance();

    totalTerpiezFound = 0;
    terpiezCaught.clear();
    caughtLocations.clear();
    startDate = DateTime.now();

    userID = generateUUID();

    await prefs.setInt('totalTerpiezFound', 0);
    await prefs.setStringList('terpiezCaught', []);
    await prefs.setStringList('caughtLocations', []);
    await prefs.setString('firstRun', startDate.toIso8601String());
    await prefs.setString('userID', userID);

    await loadServerLocations();

    try {
      print("New user ID configured on Redis: $userID");
    } catch (e) {
      print("Could not reach Redis during clear data: $e");
    }

    notifyListeners();
  }

  Future<void> saveUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('totalTerpiezFound', totalTerpiezFound);
    await prefs.setStringList('terpiezCaught', terpiezCaught);

    List<String> stringLocations = caughtLocations.map((loc) {
      return "${loc.latitude},${loc.longitude}";
    }).toList();

    await prefs.setStringList('caughtLocations', stringLocations);
  }

  int get daysPlayed {
    final cur = DateTime.now();
    return cur.difference(startDate).inDays;
  }

  Future<void> incrementTerpiez(String terpieID, double caughtLat, double caughtLon) async {
  final cleanTerpieID = terpieID.trim();

  totalTerpiezFound++;
  terpiezCaught.add(cleanTerpieID);
  caughtLocations.add(LatLng(caughtLat, caughtLon));

  terpiezLocations.removeWhere((terpie) {
    String id = terpie['id'].toString().trim();
    double lat = (terpie['lat'] as num).toDouble();
    double lon = (terpie['lon'] as num).toDouble();

    return (id == cleanTerpieID) &&
        (lat == caughtLat) &&
        (lon == caughtLon);
  });

  await saveUserData(); //use await
  notifyListeners();

  try {
    if (await LocalFileHelper.getTerpieData(cleanTerpieID) == null) {
      final details = await RedisHelper.fetchTerpieDetails(cleanTerpieID);
      
      if (details != null && details['image'] != null) {
        final imageStr = await RedisHelper.fetchImageData(details['image']);
        
        if (imageStr != null) {
          await LocalFileHelper.saveTerpieData(cleanTerpieID, details);
          await LocalFileHelper.saveTerpieImage(cleanTerpieID, imageStr);
        }
      }
    }
  } catch (e) {
    print("Background download $cleanTerpieID: $e");
  }
}

  static String generateUUID() {
    final Uuid uuid = Uuid();
    return uuid.v4();
  }
}
