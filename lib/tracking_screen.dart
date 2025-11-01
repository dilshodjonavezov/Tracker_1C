// import 'package:background_location_tracker_example/log_user_screen.dart';
// import 'package:flutter/material.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// class TrackingScreen extends StatefulWidget {
//   const TrackingScreen({Key? key}) : super(key: key);

//   @override
//   _TrackingScreenState createState() => _TrackingScreenState();
// }

// class _TrackingScreenState extends State<TrackingScreen> {
//   String? userId;

//   @override
//   void initState() {
//     super.initState();
//     _loadUserId();
//   }

//   Future<void> _loadUserId() async {
//     final prefs = await SharedPreferences.getInstance();
//     setState(() {
//       userId = prefs.getString('user_id');
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.cyan[800],
//       appBar: AppBar(
//         backgroundColor: Colors.teal,
//         foregroundColor: Colors.white,
//         title: const Text('Отслеживание активно'),
//         centerTitle: true,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.list_alt),
//             onPressed: () {
//               print('TrackingScreen: Navigating to UserLogScreen');
//               Navigator.push(
//                 context,
//                 MaterialPageRoute(builder: (context) => const UserLogScreen()),
//               );
//             },
//             tooltip: 'Просмотр истории',
//           ),
//         ],
//       ),
//       body: Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Card(
//               color: Colors.white,
//               margin: const EdgeInsets.symmetric(horizontal: 20),
//               child: Padding(
//                 padding: const EdgeInsets.all(16),
//                 child: Column(
//                   children: [
//                     Text(
//                       'USER ID:',
//                       style: TextStyle(
//                         fontSize: 18,
//                         color: Colors.grey[400],
//                       ),
//                     ),
//                     const SizedBox(height: 8),
//                     Text(
//                       userId ?? 'Загрузка...',
//                       style: const TextStyle(
//                         fontSize: 32,
//                         fontWeight: FontWeight.bold,
//                         color: Colors.black,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }