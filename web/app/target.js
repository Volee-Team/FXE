// Where the QR code's link (/app) sends people: the one place to change it.
//
// Empty until the app can be installed by members. Then, TestFlight's public
// link (https://testflight.apple.com/join/XXXXXXXX), and later the App Store's
// (https://apps.apple.com/app/idNNNNNNNNNN). Deploy with scripts/deploy-web.sh.
// Set 2026-11-03: 1.0.0 is on the App Store since 2026-10-28 (Apple's lookup
// for com.fxetennis.app gives id 6814658300; docs/live-facts.md).
export const INSTALL_URL = "https://apps.apple.com/app/fxe-tennis/id6814658300";
