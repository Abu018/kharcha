/// Base URL of the Go API, supplied at build time with
/// `--dart-define=API_BASE_URL=<url>`. There is no built-in default; when it
/// is missing every request fails with [missingApiBaseUrlMessage].
const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

const missingApiBaseUrlMessage =
    'No API address configured. Rebuild with '
    '--dart-define=API_BASE_URL=<your-api-url>.';
