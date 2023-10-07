import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class Repository {
  final int id;
  final String name;
  final String url;

  Repository({required this.id, required this.name, required this.url});

  factory Repository.fromJson(Map<String, dynamic> json) {
    return Repository(
      id: json['id'],
      name: json['name'],
      url: json['html_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
    };
  }
}

class DatabaseHelper {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await initDatabase();
    return _database!;
  }

  Future<Database> initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'github_repositories.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE repositories (
            id INTEGER PRIMARY KEY,
            name TEXT,
            url TEXT
          )
        ''');
      },
    );
  }

  Future<void> insertRepositories(List<Repository> repositories) async {
    final db = await database;
    for (var repo in repositories) {
      await db.insert('repositories', repo.toJson());
    }
  }

  Future<List<Repository>> getRepositories() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('repositories');
    return List.generate(maps.length, (i) {
      return Repository(
        id: maps[i]['id'],
        name: maps[i]['name'],
        url: maps[i]['url'],
      );
    });
  }
}

Future<List<Repository>> fetchGitHubRepositories() async {
  final response = await http.get(Uri.parse('https://api.github.com/users/hadley/repos'));

  if (response.statusCode == 200) {
    final List<dynamic> jsonResponse = json.decode(response.body);
    return jsonResponse.map((json) => Repository.fromJson(json)).toList();
  } else {
    throw Exception('Failed to load GitHub repositories');
  }
}

void showSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
    ),
  );
}

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final DatabaseHelper dbHelper = DatabaseHelper();
  final Connectivity _connectivity = Connectivity();

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    fetchDataAndStoreLocally();
  }

  Future<void> fetchDataAndStoreLocally() async {
    final connectivityResult = await _connectivity.checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      // No internet connection
      showSnackBar(_scaffoldMessengerKey.currentContext!, 'No internet connection');
      return;
    }

    try {
      final repositories = await fetchGitHubRepositories();
      await dbHelper.insertRepositories(repositories);
      showSnackBar(_scaffoldMessengerKey.currentContext!, 'Data fetched and stored locally successfully');
    } catch (e) {
      print('Error: $e');
      showSnackBar(_scaffoldMessengerKey.currentContext!, 'Error fetching or storing data');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldMessengerKey,
      appBar: AppBar(
        title: Text('GitHub Repositories'),
      ),
      body: FutureBuilder<List<Repository>>(
        future: dbHelper.getRepositories(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return CircularProgressIndicator();
          } else if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          } else {
            final repositories = snapshot.data ?? [];
            return ListView.builder(
              itemCount: repositories.length,
              itemBuilder: (context, index) {
                final repository = repositories[index];
                return ListTile(
                  title: Text(repository.name),
                  subtitle: Text(repository.url),
                );
              },
            );
          }
        },
      ),
    );
  }
}
