import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:redis/redis.dart' hide Consumer;
import 'user_state.dart';
import 'finder_tab.dart';
import 'details_tab.dart';
import 'settings_drawer.dart';
import 'notification_helper.dart';
import 'background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; 
import 'app_config.dart';

final ValueNotifier<int> totalTerpiez = ValueNotifier<int>(0);
const storage = FlutterSecureStorage();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationHelper.initializeUI();
  await initializeBackgroundService();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  int startingTab = 0; // Default to Stats (index 0)

  final NotificationAppLaunchDetails? notificationAppLaunchDetails =
      await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();

  if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
    if (notificationAppLaunchDetails?.notificationResponse?.payload == 'FINDER_TAB') {
      startingTab = 1; // Finder Tab!
    }
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => UserState(),
      child: MyApp(initialTabIndex: startingTab), 
    ),
  );
}

class MyApp extends StatelessWidget {
  final int initialTabIndex; 
  const MyApp({super.key, required this.initialTabIndex});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Terpiez',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF820101),
          primary: const Color(0xFF820101),
        ),
      ),
      home: HomePage(initialTabIndex: initialTabIndex),
    );
  }
}

class HomePage extends StatefulWidget {
  final int initialTabIndex; // Add this
  
  const HomePage({super.key, required this.initialTabIndex});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final configurationError = AppConfig.redisConfigurationError;
      if (configurationError != null) {
        _showConfigurationError(configurationError);
        return;
      }

      checkSavedCredentials();
      RedisHelper.startMonitoring();
    });

    startBackgroundTracking();
  }

  Future<void> _showConfigurationError(String message) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Configuration required'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void startBackgroundTracking() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      FlutterBackgroundService().startService();
    } else {
      print("User denied background location. Cannot run service.");
    }
  }

  Future<void> checkSavedCredentials() async {
    String? username = await storage.read(key: 'username');
    String? password = await storage.read(key: 'password');

    //print("Saved username: $username");
    //print("Saved password: $password");

    if (username == null || password == null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const LoginDialog();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          toolbarHeight: 20,
          title: const Text('Terpiez'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.blueGrey,
            tabs: [
              Tab(icon: Icon(Icons.auto_graph), text: 'Stats'),
              Tab(icon: Icon(Icons.search), text: 'Finder'),
              Tab(icon: Icon(Icons.list), text: 'List'),
            ],
          ),
        ),
        drawer: const SettingsDrawer(),
        body: const TabBarView(
          children: [StatsTab(), FinderTab(), DetailsTab()],
        ),
      ),
    );
  }
}

class LoginDialog extends StatefulWidget {
  const LoginDialog({super.key});

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isConnecting = false;

  Future<void> _attemptLogin() async {
    final configurationError = AppConfig.redisConfigurationError;
    if (configurationError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(configurationError)),
        );
      }
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isConnecting = true);

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final conn = RedisConnection();

      final Command command = await conn
          .connect(AppConfig.redisHost, AppConfig.redisPort)
          .timeout(const Duration(seconds: 1));

      await command
          .send_object(['AUTH', username, password])
          .timeout(const Duration(seconds: 1));

      RedisHelper.reportSuccess();

      await storage.write(key: 'username', value: username);
      await storage.write(key: 'password', value: password);
      if (mounted) {
        Navigator.of(context).pop(); // Close the dialog
      }
    } catch (e) {
      RedisHelper.reportFailure();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to connect. Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevents Android back button from closing it
      child: AlertDialog(
        title: const Text('Connect to UMD Redis'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your credentials to connect.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
            ],
          ),
        ),
        actions: [
          _isConnecting
              ? const Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: CircularProgressIndicator(),
                )
              : ElevatedButton(
                  onPressed: _attemptLogin,
                  child: const Text('Connect'),
                ),
        ],
      ),
    );
  }
}

class RedisHelper {
  static String? cachedUsername;
  static String? cachedPassword;

  // Null initially so no snackbar first successful launch
  static bool? isConnected;
  static Timer? probeTimer;

  static void startMonitoring() {
    if (!AppConfig.isRedisConfigured) {
      isConnected = false;
      return;
    }

    scheduleProbe();
  }

  static Future<void> loadCredentials() async {
    if (cachedUsername == null || cachedPassword == null) {
      cachedUsername = await storage.read(key: 'username');
      cachedPassword = await storage.read(key: 'password');
    }
  }

  static void scheduleProbe() {
    probeTimer?.cancel();
    if (!AppConfig.isRedisConfigured) return;

    probeTimer = Timer(const Duration(seconds: 10), runProbe);
  }

  static Future<void> runProbe() async {
    if (!AppConfig.isRedisConfigured) {
      isConnected = false;
      return;
    }

    final conn = RedisConnection();
    try {
      final command = await conn
          .connect(AppConfig.redisHost, AppConfig.redisPort)
          .timeout(const Duration(seconds: 1));

      await loadCredentials();

      if (cachedUsername != null && cachedPassword != null) {
        //no need for ping since Auth checks status
        await command
            .send_object(['AUTH', cachedUsername, cachedPassword])
            .timeout(const Duration(seconds: 1));

        reportSuccess();
      } else {
        reportFailure();
      }
    } catch (e) {
      reportFailure();
    } finally {
      await conn.close();
    }
  }

  static void reportSuccess() {
    if (isConnected == false) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Connection was restored')),
      );
    }
    isConnected = true;
    scheduleProbe();
  }

  static void reportFailure() {
    if (isConnected == true) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Connection was lost')),
      );
    }
    isConnected = false;
    scheduleProbe();
  }

  static bool get isOffline => isConnected == false;

  static Future<List<Map<String, dynamic>>> fetchAllLocations() async {
    if (!AppConfig.isRedisConfigured || isOffline) return [];

    final conn = RedisConnection();
    try {
      final command = await conn
          .connect(AppConfig.redisHost, AppConfig.redisPort)
          .timeout(const Duration(seconds: 1));

      await loadCredentials();
      await command
          .send_object(['AUTH', cachedUsername, cachedPassword])
          .timeout(const Duration(seconds: 1));
      final response = await command
          .send_object(['JSON.GET', 'locations'])
          .timeout(const Duration(seconds: 1));

      reportSuccess();

      if (response != null) {
        final List<dynamic> rawList = jsonDecode(response.toString());
        return List<Map<String, dynamic>>.from(rawList);
      }
      return [];
    } catch (e) {
      reportFailure();
      return [];
    } finally {
      await conn.close();
    }
  }

  static Future<Map<String, dynamic>?> fetchTerpieDetails(
    String terpieID,
  ) async {
    if (!AppConfig.isRedisConfigured) return null;

    final conn = RedisConnection();
    final command = await conn.connect(
      AppConfig.redisHost,
      AppConfig.redisPort,
    );

    try {
      await loadCredentials();
      await command
          .send_object(['AUTH', cachedUsername, cachedPassword])
          .timeout(const Duration(seconds: 1));
      final response = await command.send_object([
        'JSON.GET',
        'terpiez',
        '.$terpieID',
      ]);

      if (response != null) {
        final dynamic decoded = jsonDecode(response.toString());

        if (decoded is List && decoded.isNotEmpty) {
          return decoded.first as Map<String, dynamic>;
        } else if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
      return null;
    } catch (e) {
      print("Error fetching Terpie details for ID $terpieID: $e");
      return null;
    } finally {
      await conn.close();
    }
  }

  static Future<String?> fetchImageData(String imageKey) async {
    if (!AppConfig.isRedisConfigured) return null;

    final conn = RedisConnection();
    final command = await conn.connect(
      AppConfig.redisHost,
      AppConfig.redisPort,
    );

    try {
      await loadCredentials();
      await command
          .send_object(['AUTH', cachedUsername, cachedPassword])
          .timeout(const Duration(seconds: 1));

      final response = await command.send_object([
        'JSON.GET',
        'images',
        '.$imageKey',
      ]);

      if (response != null) {
        final dynamic decoded = jsonDecode(response.toString());

        if (decoded is List && decoded.isNotEmpty) {
          return decoded.first.toString();
        } else {
          return decoded.toString();
        }
      }
      return null;
    } catch (e) {
      print("Error fetching key image data  $imageKey: $e");
      return null;
    } finally {
      await conn.close();
    }
  }
}

class StatsTab extends StatelessWidget {
  const StatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Statistics',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            Align(
              alignment: Alignment.centerLeft,
              child: Consumer<UserState>(
                builder: (context, userState, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Terpiez Found: ${userState.totalTerpiez}',
                        style: const TextStyle(fontSize: 20),
                      ),
                      Text(
                        'Days Active:       ${userState.daysPlayed}',
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(height: 50),
                      Center(
                        child: Text(
                          'User: ${userState.userID}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
