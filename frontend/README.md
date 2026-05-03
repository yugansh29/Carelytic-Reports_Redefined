# Carelytic Frontend

Flutter client for clinical note generation and patient summary workflows.

## API configuration

The app supports runtime API configuration through Dart defines.

Available defines:
- API_SCHEME (default: http)
- API_HOST (default: localhost on web, 10.0.2.2 on Android emulator, 127.0.0.1 otherwise)
- API_PORT (default: 8000)
- API_BEARER_TOKEN (optional; required when backend auth is enabled)

Example:

```bash
flutter run \
	--dart-define=API_SCHEME=http \
	--dart-define=API_HOST=127.0.0.1 \
	--dart-define=API_PORT=8000 \
	--dart-define=API_BEARER_TOKEN=replace-with-token
```

For Android emulator, host should usually be 10.0.2.2.

## Notes

- API calls now use retry logic for transient failures.
- HTTP errors are surfaced to UI instead of silently returning fake clinical content.
- Privacy mode toggle now works in the dashboard and masks patient names in the visits list.
