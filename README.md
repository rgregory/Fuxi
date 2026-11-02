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
- **At Boot**: changes made with `sysctl -w` reset at restart. Fuxi can save them to `/etc/sysctl.conf`, which macOS reads at startup. A `sysctl.conf` you already had is backed up to `/etc/sysctl.conf.fuxi-backup` first. macOS services reset a few keys after startup, so restart and check that each value stuck.
- **History**: every change with its previous value and a Revert button.

## How authorization works

Every write goes through the standard macOS administrator prompt (`osascript … with administrator privileges`). Fuxi never stores your password. Keys and values are restricted to letters, digits and `. _ - : ,` before they reach the root shell.

On first launch Fuxi saves every current value as the macOS defaults, in `~/Library/Application Support/Fuxi/state.json`, so Restore Default and Revert have something to return to.

## Remove everything

```sh
sudo rm -f /etc/sysctl.conf
[ -f /etc/sysctl.conf.fuxi-backup ] && sudo mv /etc/sysctl.conf.fuxi-backup /etc/sysctl.conf
rm -rf ~/Library/Application\ Support/Fuxi
```

## License

Copyright 2026 Roger Gregory <rtgregory@gmail.com>

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
