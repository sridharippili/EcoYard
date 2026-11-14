import 'package:http/http.dart' as http;

import 'birdnet_online_provider.dart';
import 'naturelm_provider.dart';
import 'provider_chain.dart';

/// EcoYard v1's identification chain, online only:
///
/// 1. NatureLM via the GardenEar router
/// 2. BirdNET online, when NatureLM is not responsive
/// 3. neither reachable -> [ProviderChain.identify] throws honestly
///
/// On-device BirdNET is deferred, not part of v1.
ProviderChain standardOnlineChain({http.Client? client}) {
  final c = client ?? http.Client();
  return ProviderChain(
    [
      NatureLmProvider(client: c),
      BirdNetOnlineProvider(client: c),
    ],
    // The BirdNET Space can need ~20 s to wake from sleep.
    perProviderTimeout: const Duration(seconds: 40),
  );
}
