import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'user_state.dart';

class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final userState = Provider.of<UserState>(context);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.blue,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.settings, color: Colors.white, size: 40),
                SizedBox(height: 10),
                Text(
                  'Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          SwitchListTile(
            title: const Text('In-App Sounds'),
            subtitle: const Text('Toggle proximity and catch sounds'),
            value: userState.soundEnabled,
            activeColor: Colors.blue,
            secondary: Icon(
              userState.soundEnabled ? Icons.volume_up : Icons.volume_off,
              color: userState.soundEnabled ? Colors.blue : Colors.grey,
            ),
            onChanged: (bool value) {
              userState.toggleSound(value);
            },
          ),
          
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              'Clear All Data',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Resets ID, stats, and Terpiez'),
            onTap: () {
              _showClearDataConfirmation(context, userState);
            },
          ),
        ],
      ),
    );
  }

  //Confirmation Dialog Logic 
  void _showClearDataConfirmation(BuildContext context, UserState userState) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Clear All Data?'),
          content: const Text(
            'This action is irreversible. It will delete your current User ID, your days played, and all Terpiez you have caught.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(), // Just close the dialog
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.of(dialogContext).pop(); 
                
                // close drawer
                Navigator.of(context).pop(); 
                
                await userState.clearData();
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Data cleared! New User ID generated.'),
                      backgroundColor: Colors.redAccent,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              },
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}