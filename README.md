# omarchy-t2-utils

Utilities and fixes for running Linux on T2 Macs (MacBook Pro 2018-2020, MacBook Air 2018-2020, etc.)

## WiFi Fix

T2 Macs use Broadcom BCM4364 WiFi chips which can experience intermittent connection drops due to aggressive power saving. This fix disables WiFi power save.

### Quick Fix (temporary)

```bash
sudo iw dev wlan0 set power_save off
```

### Permanent Fix

```bash
# Clone the repo
git clone https://github.com/ngodn/omarchy-t2-utils.git
cd omarchy-t2-utils

# Run the installer
sudo ./scripts/install-wifi-fix.sh
```

### Manual Installation

Copy the iwd config:

```bash
sudo mkdir -p /etc/iwd
sudo cp config/iwd/main.conf /etc/iwd/main.conf
sudo systemctl restart iwd
```

## What This Fixes

- Intermittent WiFi disconnections
- Slow WiFi after idle periods
- Random connection drops during use

## Hardware Compatibility

Tested on:
- MacBook Pro with BCM4364 (brcmfmac driver)

## Additional Tips

- Prefer 5GHz networks over 2.4GHz for better performance
- Signal strength of -50 dBm or better is recommended
- Check your connection status with: `iw dev wlan0 link`

## License

MIT
