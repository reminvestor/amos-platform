Run the Flutter mobile app on iOS Simulator.

Execute the following command:

```bash
./flutter_mobile/run_ios.sh
```

This will:
1. Start Docker services if not running
2. Open iOS Simulator
3. Wait for the Rails API to be ready
4. Run the Flutter app with the correct API_BASE_URL
