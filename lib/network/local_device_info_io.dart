import 'dart:io';

Future<String> getLocalIpv4() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  final addresses = interfaces
      .expand((interface) => interface.addresses)
      .where((address) =>
          address.type == InternetAddressType.IPv4 &&
          !address.isLoopback &&
          !address.address.startsWith('169.254.'))
      .toList();
  if (addresses.isEmpty) {
    throw const SocketException(
      'No local IPv4 address found. Connect to Wi-Fi or a hotspot first.',
    );
  }
  addresses.sort((a, b) {
    bool preferred(InternetAddress value) =>
        value.address.startsWith('192.168.') ||
        value.address.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2[0-9]|3[0-1])\.').hasMatch(value.address);
    return (preferred(b) ? 1 : 0) - (preferred(a) ? 1 : 0);
  });
  return addresses.first.address;
}

String getLocalDeviceName() {
  final hostname = Platform.localHostname.trim();
  return hostname.isEmpty ? 'Plazma S device' : hostname;
}
