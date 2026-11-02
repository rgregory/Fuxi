# Fuxi

A native macOS app that reviews kernel `sysctl` settings for security and performance, and changes them after an administrator prompt.

Requires macOS 14 or later and the Xcode command-line tools (`xcode-select --install`).

## Build

```sh
./build-app.sh
open build/Fuxi.app
```

Or open `Package.swift` in Xcode and press Run.

## What it does

- **Overview**: hardware, OS, uptime, load, and how close the kernel is to its vnode, file and swap limits.
- **Findings**: each reviewed key with its current value, the recommended value and why. Select several and apply them together, or apply one at a time.
- **All Keys**: every key from `sysctl -a`, searchable. Double-click a row (or right-click › Set Value…) to change any writable key.
- **At Boot**: changes made with `sysctl -w` reset at restart. Fuxi can install `/Library/LaunchDaemons/com.fuxi.sysctl.plist`, which runs `/usr/local/sbin/fuxi-sysctl.sh` at startup.
- **History**: every change with its previous value and a Revert button.

## How authorization works

Every write goes through the standard macOS administrator prompt (`osascript … with administrator privileges`). Fuxi never stores your password. Keys and values are restricted to letters, digits and `. _ - : ,` before they reach the root shell.

On first launch Fuxi saves every current value as the macOS defaults, in `~/Library/Application Support/Fuxi/state.json`, so Restore Default and Revert have something to return to.

## Remove everything

```sh
sudo launchctl bootout system/com.fuxi.sysctl
sudo rm -f /Library/LaunchDaemons/com.fuxi.sysctl.plist /usr/local/sbin/fuxi-sysctl.sh
rm -rf ~/Library/Application\ Support/Fuxi
```

## License

Copyright 2026 Roger Gregory <rtgregory@gmail.com>

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
