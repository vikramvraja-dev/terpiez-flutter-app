import 'package:flutter/material.dart';
import 'shader_background.dart';
import 'main.dart';
import 'package:provider/provider.dart';
import 'user_state.dart';
import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:io';
import 'package:terpiez/local_file_helper.dart';

class DetailsTab extends StatelessWidget {
  const DetailsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final userState = Provider.of<UserState>(context);
    //remove duplicates by casting to set
    final caughtList = userState.terpiezCaught.toSet().toList();
    
    if (caughtList.isEmpty) {
      return const Center(
        child: Text(
          "No Terpiez caught yet. Go explore!",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      );
    }

    //For each caught species, create a lisst tab
    return ListView.builder(
      itemCount: caughtList.length,
      itemBuilder: (context, index) {
        String terpieID = caughtList[index];
        return TerpieListItem(terpieID: terpieID);
      },
    );
  }
}

class TerpieListItem extends StatefulWidget {
  final String terpieID;
  const TerpieListItem({super.key, required this.terpieID});

  @override
  State<TerpieListItem> createState() => _TerpieListItemState();
}

class _TerpieListItemState extends State<TerpieListItem> {
  String? terpieName;
  File? localThumbFile; // changed to File 
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRowData();
  }

  Future<void> _fetchRowData() async {
    Map<String, dynamic>? details = await LocalFileHelper.getTerpieData(widget.terpieID);
    File? thumbFile = await LocalFileHelper.getTerpieImageFile(widget.terpieID, isThumb: true);

    // if not found locally, fetch from Redis and save
    try {
      if (details == null || thumbFile == null) {
        details ??= await RedisHelper.fetchTerpieDetails(widget.terpieID);

        if (details != null && details['thumbnail'] != null) {
          final thumbStr = await RedisHelper.fetchImageData(details['thumbnail']);
          
          if (thumbStr != null) {
            await LocalFileHelper.saveTerpieData(widget.terpieID, details);
            await LocalFileHelper.saveTerpieImage(widget.terpieID, thumbStr, isThumb: true);
            
            thumbFile = await LocalFileHelper.getTerpieImageFile(widget.terpieID, isThumb: true);
          }
        }
      }
    } catch (e) {
      print("Error: $e");
    }

    if (mounted) {
      setState(() {
        terpieName = details?['name'];
        localThumbFile = thumbFile;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading symbol
    if (isLoading) {
      return const ListTile(
        leading: CircularProgressIndicator(),
        title: Text("Loading..."),
      );
    }

    // Once loaded
    return ListTile(
      // Hero for transition
      leading: Hero(
        tag: 'terpie_icon_${widget.terpieID}',
        child: localThumbFile != null
            ? Image.file(
                localThumbFile!,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
              )
            : const Icon(Icons.pets, size: 40, color: Colors.green), // Fallback
      ),
      title: Text(
        terpieName ?? "Unknown Terpie",
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TerpieDetailPage(
              terpieID: widget.terpieID,
            ),
          ),
        );
      },
    );
  }
}

class TerpieDetailPage extends StatefulWidget {
  final String terpieID;
  final String? thumbBase64; 

  const TerpieDetailPage({
    super.key, 
    required this.terpieID, 
    this.thumbBase64, 
  });

  @override
  State<TerpieDetailPage> createState() => _TerpieDetailPageState();
}

class _TerpieDetailPageState extends State<TerpieDetailPage> {
  Map<String, dynamic>? terpieDetails;
  //Changed from String?
  File? localImageFile; 
  List<LatLng> speciesLocations = []; 
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final userState = Provider.of<UserState>(context, listen: false);
    
    Map<String, dynamic>? details = await LocalFileHelper.getTerpieData(widget.terpieID);
    File? imgFile = await LocalFileHelper.getTerpieImageFile(widget.terpieID);
    
    // Calculate caught locations locally first 
    List<LatLng> filteredLocations = [];
    final caughtList = userState.terpiezCaught;
    final caughtCoords = userState.caughtLocations;

    for (int i = 0; i < caughtList.length; i++) {
      if (caughtList[i] == widget.terpieID) {
        if (i < caughtCoords.length) {
          filteredLocations.add(caughtCoords[i]);
        }
      }
    }

    try {
      if (details == null || imgFile == null) {
        details ??= await RedisHelper.fetchTerpieDetails(widget.terpieID);
        
        if (details != null && details['image'] != null) {
          final imageStr = await RedisHelper.fetchImageData(details['image']);
          
          if (imageStr != null) {
            await LocalFileHelper.saveTerpieData(widget.terpieID, details);
            await LocalFileHelper.saveTerpieImage(widget.terpieID, imageStr);
            imgFile = await LocalFileHelper.getTerpieImageFile(widget.terpieID);
          }
        }
      }
    } catch (e) {
      print("Error2: $e");
    }

    if (mounted) {
      setState(() {
        terpieDetails = details;
        localImageFile = imgFile;
        speciesLocations = filteredLocations; 
        isLoading = false; 
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget displayImage;
   //  check for the local file first
    if (localImageFile != null) {
      displayImage = Image.file(localImageFile!, height: 250, fit: BoxFit.contain);
    } else if (widget.thumbBase64 != null) {
      displayImage = Image.memory(base64Decode(widget.thumbBase64!), height: 250, fit: BoxFit.contain);
    } else {
      displayImage = const Icon(Icons.pets, size: 100, color: Colors.green);
    }

    return Scaffold(
      backgroundColor: Colors.transparent, 
      appBar: AppBar(
        elevation: 0,
        title: Text(
          terpieDetails != null ? terpieDetails!['name'] : 'Loading...',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          const ShaderBackground(), //shader effect to back layer
          SafeArea( 
            child: SingleChildScrollView(
              // Bug fix: Keep this section to remove strange stretch effect
              physics: const BouncingScrollPhysics(), 
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: SizedBox(
                      height: 250, 
                      child: Hero(
                        tag: 'terpie_icon_${widget.terpieID}',
                        child: displayImage,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),

                  if (isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (terpieDetails == null)
                    const Center(child: Text("Failed to load Terpie data."))
                  else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 200, 
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: FlutterMap(
                                options: MapOptions(
                                  initialCenter: speciesLocations.isNotEmpty 
                                      ? speciesLocations.first 
                                      : const LatLng(38.9869, -76.9426),
                                  initialZoom: 14.0,
                                  
                                  //removes user map input
                                  interactionOptions: const InteractionOptions(
                                    flags: InteractiveFlag.none, 
                                  ),
                                  
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName: 'com.vikram.terpiez',
                                  ),
                                  MarkerLayer(
                                    markers: speciesLocations.map((loc) => Marker(
                                      point: loc,
                                      width: 40,
                                      height: 40,
                                      child: const Icon(Icons.location_on, color: Colors.red, size: 30),
                                    )).toList(),
                                  ),
                                  SimpleAttributionWidget(
                                    source: const Text('© OpenStreetMap contributors'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 16), 

                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Stats", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              const Divider(),
                              ...terpieDetails!['stats'].entries.map(
                                (stat) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4.0),
                                  child: Text(
                                    "${stat.key[0].toUpperCase()}${stat.key.substring(1)}: ${stat.value}",
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),

                    const Text("Description", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const Divider(),
                    Text(
                      terpieDetails!['description'] ?? 'No description available.',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
