import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const zitadelClientId = '291785825778214944';
final zitadelIssuer = Uri.parse('https://fire-bhwnnt.us1.zitadel.cloud');
const callbackUrlScheme = 'com.example.flutterapp';
const userInfoEndpoint =
    'https://fire-bhwnnt.us1.zitadel.cloud/oidc/v1/userinfo';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter ZITADEL Auth',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'ZITADEL Authentication'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _busy = false;
  String? _accessToken;
  Map<String, dynamic>?
      _userInfo; // Información del usuario obtenida del endpoint
  Object? latestError;

  String _generateCodeVerifier() {
    final random = Random.secure();
    final codeVerifier = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(codeVerifier).replaceAll('=', '');
  }

  String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  Future<void> _authenticate() async {
    setState(() {
      latestError = null;
      _busy = true;
    });

    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _generateCodeChallenge(codeVerifier);

    try {
      final authUrl = Uri.https(
        zitadelIssuer.authority,
        '/oauth/v2/authorize',
        {
          'response_type': 'code',
          'client_id': zitadelClientId,
          'redirect_uri': '$callbackUrlScheme:/auth',
          'scope': 'openid profile email offline_access', // Scopes necesarios
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
        },
      ).toString();

      final result = await FlutterWebAuth2.authenticate(
          url: authUrl, callbackUrlScheme: callbackUrlScheme);

      final code = Uri.parse(result).queryParameters['code'];

      if (code != null) {
        final tokenUrl = Uri.https(zitadelIssuer.authority, '/oauth/v2/token');
        final response = await http.post(tokenUrl, body: {
          'client_id': zitadelClientId,
          'redirect_uri': '$callbackUrlScheme:/auth',
          'grant_type': 'authorization_code',
          'code': code,
          'code_verifier': codeVerifier,
        });

        if (response.statusCode == 200) {
          final responseData = jsonDecode(response.body);
          setState(() {
            _accessToken = responseData['access_token'];
          });
          await _fetchUserInfo(); // Llamamos a _fetchUserInfo para obtener los datos del usuario
        } else {
          setState(() {
            latestError = 'Error: ${response.statusCode} - ${response.body}';
          });
        }
      }
    } catch (e) {
      setState(() {
        latestError = e;
      });
    }
    setState(() {
      _busy = false;
    });
  }

  Future<void> _fetchUserInfo() async {
    if (_accessToken == null) {
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(userInfoEndpoint),
        
        headers: {
          'Authorization':
              'Bearer $_accessToken', // Pasamos el token de acceso en la cabecera
        },
        
      );

      if (response.statusCode == 200) {
        setState(() {
          _userInfo = jsonDecode(response.body);
          print(_userInfo);
        });
      } else {
        setState(() {
          latestError =
              'Error al obtener información del usuario: ${response.statusCode} - ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        latestError = e;
      });
    }
  }


  Future<void> _logout() async {
    setState(() {
      print('Access Token: $_accessToken');
      _accessToken = null;
      _userInfo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (latestError != null)
              Text(
                'Error: $latestError',
                style: const TextStyle(color: Colors.red),
              ),
            if (_busy)
              const CircularProgressIndicator()
            else if (_userInfo != null) ...[
              Text('Información del Usuario:'),
              Text('Nombre: ${_userInfo!['name'] ?? 'No disponible'}'),
              Text('Correo: ${_userInfo!['email'] ?? 'No disponible'}'),
              // Puedes mostrar otros datos según lo que devuelva el endpoint de userinfo
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: ElevatedButton(
                  onPressed: _logout,
                  child: const Text('Logout'),
                ),
              ),
            ] else ...[
              const Text('No estás autenticado.'),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Login'),
                  onPressed: _authenticate,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
