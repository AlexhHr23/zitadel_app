import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:oidc/oidc.dart';
import 'package:oidc_default_store/oidc_default_store.dart';

// URL de ZITADEL + ID de cliente
const zitadelClientId = '292333157821289794';
final zitadelIssuer = Uri.parse('https://public-3dvddc.zitadel.cloud');
const callbackUrlScheme = 'com.example.flutterapp';

/// This will be the current url of the page + /auth.html added to it.
final baseUri = Uri.base;
final webCallbackUrl = Uri.base.replace(path: 'auth.html');

/// for web platforms, we use http://website-url.com/auth.html
/// for mobile platforms, we use `com.example.flutterapp:/auth`
final redirectUri =
    kIsWeb ? webCallbackUrl : Uri(scheme: callbackUrlScheme, path: '/auth');

final userManager = OidcUserManager.lazy(
  discoveryDocumentUri: OidcUtils.getOpenIdConfigWellKnownUri(zitadelIssuer),
  clientCredentials:
      const OidcClientAuthentication.none(clientId: zitadelClientId),
  store: OidcDefaultStore(),
  settings: OidcUserManagerSettings(
    redirectUri: redirectUri,
    postLogoutRedirectUri: redirectUri,
    scope: ['openid', 'profile', 'email', 'offline_access'],
  ),
);

final _secureStorage = FlutterSecureStorage();
late Future<void> initFuture;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initFuture = userManager.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter ZITADEL Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      builder: (context, child) {
        return FutureBuilder(
          future: initFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorWidget(snapshot.error.toString());
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Material(
                child: Center(
                  child: CircularProgressIndicator.adaptive(),
                ),
              );
            }
            return child!;
          },
        );
      },
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

  /// Test if there is a logged in user.
  bool get _authenticated => _currentUser != null;

  /// To get the access token.
  String? get accessToken => _currentUser?.token.accessToken;

  /// To get the id token.
  String? get idToken => _currentUser?.idToken;

  /// To access the claims.
  String? get _username {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return null;
    }
    final claims = currentUser.aggregatedClaims;
    return '${claims['given_name']} ${claims['family_name']}';
  }

  OidcUser? get _currentUser => userManager.currentUser;

  // Generar code_verifier
  String generateCodeVerifier() {
    final rand = Random.secure();
    final codeVerifier = List<int>.generate(128, (index) => rand.nextInt(256));
    return base64UrlEncode(codeVerifier).replaceAll('=', '');
  }

  // Generar code_challenge desde el code_verifier
  String generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  Future<void> _authenticate() async {
    setState(() {
      latestError = null;
      _busy = true;
    });
    try {
      final codeVerifier = generateCodeVerifier();
      final codeChallenge = generateCodeChallenge(codeVerifier);

      // Llamada a login con flutter_web_auth_2 para iniciar el flujo de autenticación
      final result = await FlutterWebAuth2.authenticate(
        url: "${zitadelIssuer.toString()}/oauth/v2/authorize?client_id=$zitadelClientId&redirect_uri=$redirectUri&response_type=code&scope=openid%20profile%20email%20offline_access&code_challenge=$codeChallenge&code_challenge_method=S256",
        callbackUrlScheme: callbackUrlScheme,
      );

      // Obtiene el código de autorización desde el resultado de la autenticación
      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) {
        throw Exception("No authorization code returned");
      }

      // Solicita el token de acceso utilizando el código de autorización
      final response = await http.post(
        Uri.parse('${zitadelIssuer.toString()}/oauth/v2/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'client_id': zitadelClientId,
          'code': code,
          'redirect_uri': redirectUri.toString(),
          'code_verifier': codeVerifier, // Usa el code_verifier para verificar el token
        },
      );

      if (response.statusCode == 200) {
        final tokenData = json.decode(response.body);
        await _secureStorage.write(key: 'access_token', value: tokenData['access_token']);
        await _secureStorage.write(key: 'refresh_token', value: tokenData['refresh_token']);
      } else {
        print('Failed to retrieve access token: ${response.statusCode} - ${response.body}');
        throw Exception("Failed to retrieve access token");
      }
    } catch (e) {
      print(e);
      setState(() {
        latestError = e;
      });
    } finally {
      setState(() {
        _busy = false;
      });
    }
  }

  Future<void> _logout() async {
    setState(() {
      latestError = null;
      _busy = true;
    });
    try {
      await userManager.logout();
      await _secureStorage.delete(key: 'access_token');
      await _secureStorage.delete(key: 'refresh_token');
    } catch (e) {
      latestError = e;
    } finally {
      setState(() {
        _busy = false;
      });
    }
  }

  Future<bool> _isAuthenticated() async {
    final token = await _secureStorage.read(key: 'access_token');
    return token != null;
  }

  @override
  void initState() {
    super.initState();
    _checkAuthenticationStatus();
  }

  Future<void> _checkAuthenticationStatus() async {
    bool isAuthenticated = await _isAuthenticated();
    if (isAuthenticated) {
      setState(() {
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (latestError != null)
                Text('Error: $latestError')
              else if (_busy)
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Busy, logging in."),
                    Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  ],
                )
              else ...[
                FutureBuilder<bool>(
                  future: _isAuthenticated(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return CircularProgressIndicator();
                    }
                    if (snapshot.hasData && snapshot.data!) {
                      return Column(
                        children: [
                          Text('Hello $_username!'),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            child: ElevatedButton(
                              onPressed: _logout,
                              child: const Text('Logout'),
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          const Text('You are not authenticated.'),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.fingerprint),
                              label: const Text('Login'),
                              onPressed: _authenticate,
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
