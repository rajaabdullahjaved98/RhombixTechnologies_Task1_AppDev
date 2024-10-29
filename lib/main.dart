import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:college_reminder_app/models/reminder.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Karachi'));
  await Hive.initFlutter();
  Hive.registerAdapter(ReminderAdapter());
  await Hive.openBox<Reminder>('reminders');

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Reminder App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: ReminderListPage(),
    );
  }
}

class ReminderListPage extends StatefulWidget {
  @override
  _ReminderListPageState createState() => _ReminderListPageState();
}

class _ReminderListPageState extends State<ReminderListPage> {
  late Box<Reminder> reminderBox;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    reminderBox = Hive.box<Reminder>('reminders');
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings();

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    if (Platform.isAndroid && await _checkAndRequestNotificationPermission()) {
      _showStartupNotification();
    }
  }

  Future<bool> _checkAndRequestNotificationPermission() async {
    var status = await Permission.notification.status;
    if (status.isDenied || status.isRestricted || status.isPermanentlyDenied) {
      status = await Permission.notification.request();
    }
    return status.isGranted;
  }

  Future<void> _showStartupNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'startup_channel',
      'Startup Notifications',
      channelDescription: 'Notification displayed on app startup',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );
    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      'Welcome Back!',
      'The Reminder App is now running.',
      platformChannelSpecifics,
    );
  }

  Future<void> scheduleReminderNotification(Reminder reminder) async {
    final notificationTime = tz.TZDateTime.from(
      reminder.dateTime.subtract(Duration(minutes: 2)),
      tz.local,
    );

    developer.log('Scheduled Notification for: ${notificationTime.toString()}');

    if (notificationTime.isAfter(tz.TZDateTime.now(tz.local))) {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
        'reminder_channel',
        'Reminders',
        channelDescription: 'Channel for reminder notifications',
        importance: Importance.max,
        priority: Priority.high,
      );

      const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

      await flutterLocalNotificationsPlugin.zonedSchedule(
        reminder.hashCode,
        'Alert!',
        '${reminder.title} is starting in 2 minutes!',
        notificationTime,
        platformChannelSpecifics,
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dateAndTime,
      );

      developer.log('Notification scheduled successfully');
    } else {
      developer.log('Notification time is in the past. Notification not scheduled.');
    }
  }

  List<Reminder> _getSortedReminders() {
    List<Reminder> reminders = reminderBox.values.toList();
    reminders.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return reminders;
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat.yMMMd().add_jm().format(dateTime);
  }

  void _showReminderDetails(Reminder reminder) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(reminder.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Date: ${_formatDateTime(reminder.dateTime)}"),
              SizedBox(height: 8.0),
              Text("Description: ${reminder.description}"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _deleteReminder(int index) {
    final reminder = reminderBox.getAt(index);
    flutterLocalNotificationsPlugin.cancel(reminder.hashCode); // Cancel the notification
    reminderBox.deleteAt(index); // Delete the reminder from Hive
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Reminders'),
        backgroundColor: Colors.blueAccent,
      ),
      body: ValueListenableBuilder(
        valueListenable: reminderBox.listenable(),
        builder: (context, Box<Reminder> box, _) {
          final reminders = _getSortedReminders();

          if (reminders.isEmpty) {
            return Center(child: Text('No reminders yet!'));
          }

          return ListView.builder(
            itemCount: reminders.length,
            itemBuilder: (context, index) {
              final reminder = reminders[index];
              return Card(
                margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  onTap: () => _showReminderDetails(reminder),
                  title: Text(
                    reminder.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    _formatDateTime(reminder.dateTime),
                    style: TextStyle(
                      color: Colors.grey[600],
                    ),
                  ),
                  leading: Icon(
                    Icons.notifications,
                    color: Colors.blueAccent,
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () {
                      setState(() {
                        _deleteReminder(index);
                      });
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddReminderDialog(context);
        },
        child: Icon(Icons.add),
      ),
    );
  }

  void _showAddReminderDialog(BuildContext context) {
    String title = '';
    String description = '';
    DateTime? reminderDate;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Add Reminder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(hintText: 'Title'),
                onChanged: (value) => title = value,
              ),
              TextField(
                decoration: InputDecoration(hintText: 'Description'),
                onChanged: (value) => description = value,
              ),
              ElevatedButton(
                onPressed: () async {
                  DateTime? selectedDate = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100),
                  );
                  if (selectedDate != null) {
                    reminderDate = selectedDate;
                  }
                },
                child: Text('Choose Date'),
              ),
              ElevatedButton(
                onPressed: () async {
                  TimeOfDay? selectedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (selectedTime != null) {
                    reminderDate = reminderDate?.add(
                      Duration(hours: selectedTime.hour, minutes: selectedTime.minute),
                    );
                  }
                },
                child: Text('Choose Time'),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                if (title.isNotEmpty &&
                    description.isNotEmpty &&
                    reminderDate != null) {
                  _addReminder(title, description, reminderDate!);
                  Navigator.pop(dialogContext);
                }
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _addReminder(String title, String description, DateTime dateTime) {
    final reminder = Reminder(
      title: title,
      description: description,
      dateTime: dateTime,
    );
    reminderBox.add(reminder);
    scheduleReminderNotification(reminder);
  }
}
