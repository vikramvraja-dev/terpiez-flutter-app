import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'user_state.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:terpiez/local_file_helper.dart';
import 'main.dart';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

class FinderTab extends StatefulWidget {
  const FinderTab({super.key});

  @override
  State<FinderTab> createState() => _FinderTabState();
}

class _FinderTabState extends State<FinderTab> {
  LatLng? location;
  LatLng? closestTerpieCoords;
  double closestTerpieDistance = double.infinity;
  String? closestTerpieID;
  StreamSubscription<Position>? positionStream;
  final MapController mapController = MapController();
  bool isProcessingCatch = false;

  final AudioPlayer audioPlayer = AudioPlayer();
  String? lastNotifiedTerpieID;

  StreamSubscription<AccelerometerEvent>? accelSub;
  bool isShaking = false;

  @override
  void initState() {
    super.initState();
    initializeLocation();

    accelSub = accelerometerEventStream().listen((event) {
      final magnitude =
          event.x.abs() +
          event.y.abs() +
          event.z.abs() -
          9.8; //don't forget about gravity
      final shaking = magnitude >= 10.0;
      if (shaking && closestTerpieDistance <= 10.0 && !isProcessingCatch) {
        isProcessingCatch = true;
        catchTerpie();

        if (mounted) {
          final userState = Provider.of<UserState>(context, listen: false);
          if (userState.soundEnabled) {
        audioPlayer.play(AssetSource('sounds/boop.mp3'));
          }
        }

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) isProcessingCatch = false;
        });
      }
      if (shaking != isShaking) {
        setState(() => isShaking = shaking);
      }
    });
  }

  Future<void> initializeLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();

    //check permissions
    if (permission == LocationPermission.deniedForever) return;

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Position initialPosition = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        location = LatLng(initialPosition.latitude, initialPosition.longitude);
        updateClosestTerpie();

        checkProximityNotification();

        mapController.move(location!, 15.0);
      });
    }

    positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 2,
          ),
        ).listen((Position position) {
          if (mounted) {
            setState(() {
              location = LatLng(position.latitude, position.longitude);
              updateClosestTerpie();

              checkProximityNotification();

              //center map on player
              mapController.move(location!, 15.0);
            });
          }
        });
  }

  void updateClosestTerpie() {
    final userState = Provider.of<UserState>(context, listen: false);
    final terpiezLocations = userState.terpiezLocations;

    if (location == null || terpiezLocations.isEmpty) {
      closestTerpieDistance = double.infinity;
      closestTerpieID = null;
      return;
    }

    double minDistance = double.infinity;
    String? closestID;

    for (var terpie in terpiezLocations) {
      double distance = Geolocator.distanceBetween(
        location!.latitude,
        location!.longitude,
        terpie['lat'],
        terpie['lon'],
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestTerpieCoords = LatLng(
          (terpie['lat'] as num).toDouble(),
          (terpie['lon'] as num).toDouble(),
        );
        closestID = terpie['id'].toString();
      }
      //for every terpie, check distance and update closest
    }

    closestTerpieDistance = minDistance;
    closestTerpieID = closestID;
  }

  void catchTerpie() {
    final userState = Provider.of<UserState>(context, listen: false);

    if (closestTerpieID != null) {
      final String caughtId = closestTerpieID!;

      userState.incrementTerpiez(
        closestTerpieID!,
        closestTerpieCoords!.latitude,
        closestTerpieCoords!.longitude,
      );

      showCaughtDialog(caughtId, userState);
    } else {
      throw Exception("TERPIE IS NULL!!!!");
    }

    setState(() {
      // Recalculate distance to the NEXT closest one
      updateClosestTerpie();
    });
  }

  Future<Map<String, dynamic>> fetchDialogData(String terpieID) async {
    Map<String, dynamic>? details = await LocalFileHelper.getTerpieData(
      terpieID,
    );
    File? imgFile = await LocalFileHelper.getTerpieImageFile(terpieID);

    try {
      if (details == null || imgFile == null) {
        details ??= await RedisHelper.fetchTerpieDetails(terpieID);

        if (details != null && details['image'] != null) {
          final imageStr = await RedisHelper.fetchImageData(details['image']);

          if (imageStr != null) {
            await LocalFileHelper.saveTerpieData(terpieID, details);
            await LocalFileHelper.saveTerpieImage(terpieID, imageStr);
            imgFile = await LocalFileHelper.getTerpieImageFile(terpieID);
          }
        }
      }
    } catch (e) {
      print("Error fetching dialog data: $e");
    }
    return {'name': details?['name'] ?? 'Unknown Terpie', 'file': imgFile};
  }

void showCaughtDialog(String caughtId, UserState userState) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Gotcha!',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
          ),
          content: FutureBuilder<Map<String, dynamic>>(
            future: fetchDialogData(caughtId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 20),
                      Text("Analyzing Terpie..."),
                    ],
                  ),
                );
              }

              final terpieName = snapshot.data?['name'] as String? ?? 'Unknown';
              final imgFile = snapshot.data?['file'] as File?;

              // Shrink the image slightly to save space
              final double imageSize = isLandscape ? 80.0 : 120.0;

              Widget displayImage;
              if (imgFile != null) {
                displayImage = Image.file(
                  imgFile,
                  height: imageSize,
                  width: imageSize,
                  fit: BoxFit.cover,
                );
              } else {
                displayImage = Icon(
                  Icons.pets,
                  size: imageSize - 20, // Adjust icon size accordingly
                  color: Colors.green,
                );
              }

              Widget textContent = Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'You caught $terpieName!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Added to your collection.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
              );

              return SingleChildScrollView(
                child: isLandscape
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: displayImage,
                          ),
                          const SizedBox(width: 20),
                          Flexible(child: textContent), // Flexible prevents text overflow
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: displayImage,
                          ),
                          const SizedBox(height: 20),
                          textContent,
                        ],
                      ),
              );
            },
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text('Add to library'),
              ),
            ),
          ],
        );
      },
    );
  }


  void checkProximityNotification() {
    if (closestTerpieDistance <= 20.0 && closestTerpieDistance > 10.0) {
      if (lastNotifiedTerpieID != closestTerpieID) {
        lastNotifiedTerpieID = closestTerpieID;

        // Play the ping sound
        if (mounted) {
          final userState = Provider.of<UserState>(context, listen: false);
          if (userState.soundEnabled) {
        audioPlayer.play(AssetSource('sounds/ping.mp3'));
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Terpiez is close!'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
            backgroundColor: Colors.blueAccent,
          ),
        );
      }
    } else if (closestTerpieDistance > 20.0) {
      // If the user walks out of range, reset it so it can trigger again later
      lastNotifiedTerpieID = null;
    }
  }

  void centerOnUser() {
    if (location != null) {
      mapController.move(location!, 15.0);
    }
  }

  @override
  void dispose() {
    positionStream?.cancel();
    mapController.dispose();
    accelSub?.cancel(); 
    audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userState = Provider.of<UserState>(context);

    updateClosestTerpie();

    final bool canCatch = closestTerpieDistance <= 10.0;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    /*
    void Function()? buttonAction;
    String buttonText;

    if (canCatch) {
      buttonAction = catchTerpie;
      buttonText = 'CATCH TERPIE!';
    } else {
      buttonAction = null;
      buttonText = 'Too far away';
    }*/

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Flex(
          direction: isLandscape ? Axis.horizontal : Axis.vertical,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: FlutterMap(
                  mapController: mapController,
                  options: MapOptions(
                    initialCenter: location ?? const LatLng(38.9869, -76.9426),
                    initialZoom: 15.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.vikram.terpiez',
                    ),
                    MarkerLayer(
                      markers: [
                        if (closestTerpieCoords != null)
                          Marker(
                            point: closestTerpieCoords!,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.pets,
                              color: Colors.red,
                              size: 30,
                            ),
                          ),
                        if (location != null)
                          Marker(
                            point: location!,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.my_location,
                              color: Colors.blue,
                              size: 30,
                            ),
                          ),
                      ],
                    ),
                    SimpleAttributionWidget(
                      source: const Text('© OpenStreetMap contributors'),
                    ),
                  ],
                ),
              ),
            ),

            if (!isLandscape)
              const SizedBox(height: 24)
            else
              const SizedBox(width: 24),

            SizedBox(
              width: isLandscape ? 300 : null,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        location == null
                            ? 'Locating...'
                            : 'Closest Terpiez: ${closestTerpieDistance.toStringAsFixed(1)} m',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 16),

                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: canCatch
                              ? (isShaking
                                    ? Colors
                                          .green
                                          .shade400 // actively shaking + in range
                                    : Colors
                                          .green
                                          .shade100) // in range, not shaking
                              : Colors.grey.shade200, // out of range
                          border: Border.all(
                            color: canCatch
                                ? Colors.green.shade600
                                : Colors.grey.shade400,
                            width: canCatch ? 2.0 : 1.0,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              canCatch
                                  ? Icons.vibration
                                  : Icons.location_searching,
                              size: 36,
                              color: canCatch
                                  ? (isShaking
                                        ? Colors.green.shade900
                                        : Colors.green.shade700)
                                  : Colors.grey.shade500,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              canCatch
                                  ? (isShaking
                                        ? 'Catching...'
                                        : 'Shake to catch!')
                                  : 'Get closer to catch',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: canCatch
                                    ? (isShaking
                                          ? Colors.green.shade900
                                          : Colors.green.shade700)
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
