# EcoGraph app (Flutter)

One codebase for iOS, Android and web. On a phone it is the case queue with a case screen (Evidence, Why, Query, Ask) and a
decision bar; when the agent has proposed an action, a banner shows it above the tabs. In a window 1320 px wide or more it turns into a three-pane review console: case rail, graph, and Why / Query / Ask.

The app is a thin client. It never holds the Claude key: the backend does, and the app only calls the JSON API in
[`../API_CONTRACT.md`](../API_CONTRACT.md). All data is synthetic.

## Run it

1. Start the backend from the repo root: `PYTHONPATH=. python -m eco.server 8000`
2. In `app/`:

```bash
flutter pub get
flutter run -d chrome          # web console (open a wide window)
flutter run                    # iOS simulator or Android emulator, whichever is running
```

The app finds the backend by itself: `127.0.0.1:8000` on web and the iOS simulator, `10.0.2.2:8000` on the Android emulator,
and the page's own origin when the web build is served by the API. To point it somewhere else:

```bash
flutter run -d chrome --dart-define=ECO_API=https://your-server --dart-define=ECO_TOKEN=your-token
flutter build apk --release --dart-define=ECO_API=https://your-server --dart-define=ECO_TOKEN=your-token
flutter build web --release        # then copy build/web to ../web_app so the API serves it
```

For a real Android phone over http, `AndroidManifest.xml` already allows INTERNET and cleartext traffic.
For iOS, `Info.plist` allows local-network http (`NSAllowsLocalNetworking`).

## Files

| File | What it holds |
|---|---|
| `lib/eco_api.dart` | Typed client for the API: cases, case detail, decisions, audit log, Ask |
| `lib/theme.dart` | Colours, text styles, shared widgets (stamps, tick meter, buttons) |
| `lib/graph.dart` | `CustomPainter` that draws the evidence graph from the server's 0..1 layout |
| `lib/panels.dart` | Evidence, Why, Query, Ask, the agent-proposal banner and tag, the decision bar and confirm sheet |
| `lib/case_screen.dart` | Phone case screen, "decision recorded" screen, audit log |
| `lib/main.dart` | App, queue (phone) and review console (wide) |

## Fonts

Schibsted Grotesk and JetBrains Mono, bundled in `assets/fonts/` under the SIL Open Font License (licence files included).

## Tests

`flutter test` parses sample API payloads. `flutter analyze` should be clean.
