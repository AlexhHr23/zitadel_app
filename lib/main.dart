import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:oidc/oidc.dart';
import 'package:oidc_default_store/oidc_default_store.dart';

/// URL de ZITADEL + ID de cliente.
/// puedes reemplazar las llamadas a String.fromEnvironment(*) con valores reales
/// si no deseas pasarlos dinámicamente.
final zitadelIssuer = Uri.parse('https://fire-bhwnnt.us1.zitadel.cloud');
const zitadelClientId = '291785825778214944';

/// Este debería ser el ID de paquete de la aplicación.
const callbackUrlScheme = 'com.example.flutterapp';

/// Esta será la URL actual de la página + /auth.html agregado a ella.
final baseUri = Uri.base;
final webCallbackUrl = Uri.base.replace(path: 'auth.html');

/// para plataformas web, usamos http://website-url.com/auth.html
///
/// para plataformas móviles, usamos `com.zitadel.zitadelflutter:/`
final redirectUri =
    kIsWeb ? webCallbackUrl : Uri(scheme: callbackUrlScheme, path: '/auth');

final userManager = OidcUserManager.lazy(
  discoveryDocumentUri: OidcUtils.getOpenIdConfigWellKnownUri(zitadelIssuer),
  clientCredentials:
      const OidcClientAuthentication.none(clientId: zitadelClientId),
  store: OidcDefaultStore(),
  settings: OidcUserManagerSettings(
    redirectUri: redirectUri,
    // el mismo redirectUri puede usarse también para el post logout.
    postLogoutRedirectUri: redirectUri,
    scope: ['openid', 'profile', 'email', 'offline_access'],
  ),
);
late Future<void> initFuture;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initFuture = userManager.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Este widget es la raíz de tu aplicación.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      builder: (context, child) {
        // Muestra un widget de carga mientras la app se está inicializando.
        // Esto se puede usar para mostrar una pantalla de bienvenida, por ejemplo.
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

  /// Verifica si hay un usuario registrado.
  bool get _authenticated => _currentUser != null;

  /// Para obtener el access token.
  String? get accessToken => _currentUser?.token.accessToken;

  /// Para obtener el id token.
  String? get idToken => _currentUser?.idToken;

  /// Para acceder a los claims.
  String? get _username {
    final currentUser = _currentUser;
    if (currentUser == null) {
      return null;
    }
    final claims = currentUser.aggregatedClaims;
    return '${claims['given_name']} ${claims['family_name']}';
  }

  OidcUser? get _currentUser => userManager.currentUser;

  Future<void> _authenticate() async {
  setState(() {
    latestError = null;
    _busy = true;
  });
  try {
    print("Iniciando el flujo de autenticación...");
    final user = await userManager.loginAuthorizationCodeFlow();

    if (user == null) {
      print("No se pudo iniciar sesión.");
      return;
    }

    // Verificar si se ha recibido el refresh_token
    final refreshToken = user.token.refreshToken;
    if (refreshToken != null) {
      print("Refresh Token recibido: $refreshToken");
    } else {
      print("No se recibió un Refresh Token.");
    }

    print("Access Token: ${user.token.accessToken}");

  } catch (e) {
    print("Error durante la autenticación: $e");
    latestError = e;
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
      await userManager.logout();
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
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (latestError != null)
                ErrorWidget(latestError!)
              else ...[
                if (_busy)
                  const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Ocupado, iniciando sesión."),
                      Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    ],
                  )
                else ...[
                  if (_authenticated) ...[
                    Text(
                      '¡Hola $_username!',
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}
