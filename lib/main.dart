import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:oidc/oidc.dart';
import 'package:oidc_default_store/oidc_default_store.dart';

final zitadelIssuer = Uri.parse('https://public-3dvddc.zitadel.cloud');
const zitadelClientId = '292333157821289794';
const callbackUrlScheme = 'com.example.flutterapp';
final storage = FlutterSecureStorage();

/// Configuración del OidcUserManager para manejar los tokens y la autenticación.
final userManager = OidcUserManager.lazy(
  discoveryDocumentUri: OidcUtils.getOpenIdConfigWellKnownUri(zitadelIssuer),
  clientCredentials: const OidcClientAuthentication.none(clientId: zitadelClientId),
  store: OidcDefaultStore(),
  settings: OidcUserManagerSettings(
    redirectUri: Uri(scheme: callbackUrlScheme, path: '/auth'),
    postLogoutRedirectUri: Uri(scheme: callbackUrlScheme, path: '/auth'),
    scope: ['openid', 'profile', 'email', 'offline_access'],
  ),
);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter ZITADEL Authentication',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter ZITADEL Quickstart'),
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
  Object? latestError;
  String? accessToken;
  String? idToken;

  /// Función para generar un code_verifier aleatorio
  String _generateCodeVerifier() {
    final random = Random.secure();
    final values = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }

  /// Función para generar el code_challenge a partir del code_verifier
  String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  Future<void> _authenticate() async {
    setState(() {
      latestError = null;
      _busy = true;
    });

    try {
      // Asegúrate de inicializar userManager antes de usarlo
      await userManager.init();

      // Generar el code_verifier y el code_challenge para PKCE
      final codeVerifier = _generateCodeVerifier();
      final codeChallenge = _generateCodeChallenge(codeVerifier);

      // Construir la URL de autenticación con PKCE
      final discoveryDocument = await userManager.discoveryDocument;
      final authorizationEndpoint = discoveryDocument.authorizationEndpoint;
      final authorizationUrl = Uri(
        scheme: authorizationEndpoint?.scheme,
        host: authorizationEndpoint?.host,
        path: authorizationEndpoint?.path,
        queryParameters: {
          'client_id': zitadelClientId,
          'redirect_uri': '$callbackUrlScheme:/auth',
          'response_type': 'code',
          'scope': 'openid profile email offline_access',
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
        },
      ).toString();

      // Abrir el navegador para autenticar usando FlutterWebAuth2
      final resultUrl = await FlutterWebAuth2.authenticate(
        url: authorizationUrl,
        callbackUrlScheme: callbackUrlScheme,
      );

      // Extraer el código de autorización de la URL de redirección
      final uri = Uri.parse(resultUrl);
      final authCode = uri.queryParameters['code'];
      if (authCode == null) {
        throw Exception("No se recibió ningún código de autorización.");
      }

      // Intercambiar el código de autorización por tokens
      final tokenUrl = Uri.parse('${zitadelIssuer.toString()}/oauth/v2/token');
      final response = await http.post(
        tokenUrl,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'client_id': zitadelClientId,
          'grant_type': 'authorization_code',
          'code': authCode,
          'redirect_uri': '$callbackUrlScheme:/auth',
          'code_verifier': codeVerifier,
        },
      );

      if (response.statusCode == 200) {
        final tokenData = json.decode(response.body);
        accessToken = tokenData['access_token'];
        idToken = tokenData['id_token'];
        final refreshToken = tokenData['refresh_token'];

        // Guardar los tokens en almacenamiento seguro
        await storage.write(key: 'access_token', value: accessToken);
        await storage.write(key: 'id_token', value: idToken);
        await storage.write(key: 'refresh_token', value: refreshToken);

        print("Access Token: $accessToken");
        print("ID Token: $idToken");
        print("Refresh Token: $refreshToken");
      } else {
        throw Exception("Error al intercambiar el código de autorización: ${response.body}");
      }
    } catch (e) {
      latestError = e;
      print("Error durante la autenticación: $e");
    }

    setState(() {
      _busy = false;
    });
  }

  Future<void> _logout() async {
    setState(() {
      latestError = null;
      _busy = true;
    });
    try {
      await storage.delete(key: 'access_token');
      await storage.delete(key: 'id_token');
      await storage.delete(key: 'refresh_token');
      accessToken = null;
      idToken = null;
    } catch (e) {
      latestError = e;
    }
    setState(() {
      _busy = false;
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
                "Error: $latestError",
                style: const TextStyle(color: Colors.red),
              )
            else if (_busy)
              const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Iniciando sesión..."),
                  Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                ],
              )
            else if (accessToken != null) ...[
              Text(
                '¡Autenticado!',
              ),
              Text(
                'Access Token: $accessToken',
              ),
              Text(
                'ID Token: $idToken',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: ElevatedButton(
                  onPressed: _logout,
                  child: const Text('Cerrar sesión'),
                ),
              ),
            ] else ...[
              const Text(
                'No estás autenticado.',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Iniciar sesión'),
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
