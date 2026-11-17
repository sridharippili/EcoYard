import 'package:http/http.dart' as http;

import 'birdnet_online_provider.dart';
import 'identification.dart';
import 'naturelm_provider.dart';
import 'provider_chain.dart';

/// EcoYard v1's identification chain, online only:
///
/// 1. NatureLM via the GardenEar router
/// 2. BirdNET online, when NatureLM is not responsive
/// 3. neither reachable -> [ProviderChain.identify] throws honestly
///
/// With [local] (the offline model), it goes first. While the model is not
/// on the phone it is skipped and the chain is exactly the one above.
ProviderChain standardOnlineChain({
  http.Client? client,
  IdentificationProvider? local,
}) {
  final c = client ?? http.Client();
  return ProviderChain(
    [
      if (local != null) local,
      NatureLmProvider(client: c),
      BirdNetOnlineProvider(client: c),
    ],
    // The BirdNET Space can need ~20 s to wake from sleep.
    perProviderTimeout: const Duration(seconds: 40),
  );
}
