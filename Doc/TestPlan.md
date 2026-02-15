
# API Key Testing Plan

1. Fresh Install Tests
- Delete app
- Install fresh
- Verify first key fetch works
- Check key is cached in Keychain

2. Cache Tests
- Force quit app
- Relaunch
- Verify cached key is used from Keychain
- Delete Keychain entry for the key
- Verify new fetch occurs

3. Concurrent Access Tests
- Delete Keychain entry for the key
- Rapidly tap multiple API-using features
- Verify app handles concurrent requests gracefully

4. Error Cases
- Enable airplane mode
- Verify graceful handling of no network
- Verify cached keys still work from Keychain
