# flutter_application_1

Minimal Flutter app that:

- Fetches all Mailchimp campaigns
- Fetches HTML content for each campaign
- Sorts campaigns by date (newest first)
- Shows campaign title/date buttons on the main screen
- Opens a detail screen that renders campaign HTML when tapped

## Run

For local development, store secrets in a file at the project root named `secrets.dev.json` (this file is gitignored):

```json
{
	"MAILCHIMP_API_KEY": "your_api_key-usX",
	"MAILCHIMP_SERVER_PREFIX": "usX"
}
```

You can copy from `secrets.dev.example.json`.

Then run:

```bash
flutter run --dart-define-from-file=secrets.dev.json
```

Alternative (less safe because it can leak into shell history):

```bash
flutter run \
	--dart-define=MAILCHIMP_API_KEY=your_api_key-usX
```

Optional (only if server prefix cannot be inferred from your API key):

```bash
flutter run \
	--dart-define=MAILCHIMP_API_KEY=your_api_key \
	--dart-define=MAILCHIMP_SERVER_PREFIX=usX
```

## Security note

For production, do not ship Mailchimp API keys inside the Flutter app. Put the key on a backend service and call that backend from the app.
