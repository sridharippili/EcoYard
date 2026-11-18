# Third-party notices

EcoYard uses the following. Each keeps its own licence and terms.

## Models and services

| What | Used for | Terms |
| --- | --- | --- |
| **BirdNET** V2.4, K. Lisa Yang Center for Conservation Bioacoustics (Cornell Lab of Ornithology) and Chemnitz University of Technology | The offline model on the phone, and the BirdNET online service | **CC BY-NC-SA 4.0: non-commercial, attribution, share-alike.** Commercial use needs a licence from the BirdNET team. The model files are **not in this repository**: the app downloads them at run time from the BirdNET-Analyzer v1.5.1 release on GitHub, and checks their size and SHA-256 first (`content/offline_model.json`). |
| **NatureLM-audio**, Earth Species Project | The online identification service (run in the owner's own notebook, reached through a router) | See the NatureLM-audio project |
| **Open-Meteo** | Weather on the Home screen (only a rounded location or town is sent) | Free weather API; its terms ask for attribution and limit commercial use |
| **Wikipedia and Wikimedia Commons** | Species photos looked up at run time (only the species name is sent) | Each photo carries its own licence; only public domain, CC0, CC BY and CC BY-SA are used |

## Photographs

The 25 bundled photos in `app/assets/photos/` come from Wikimedia Commons. The
author, licence and source of every one are in
[`content/photo_credits.json`](content/photo_credits.json) and are shown in the
app under Settings > About > Photo credits. Most are CC BY-SA 3.0/4.0 or CC BY
(attribution is required, and share-alike applies to adaptations); two are in
the public domain. Photos found at run time are credited under the photo.

## Software

Dart and Flutter packages are listed in each `pubspec.yaml`; their licences are
available through `flutter pub deps` and the app's licence page. Notable ones:
`sqflite`, `http`, `record`, `geolocator`, `share_plus`,
`flutter_local_notifications`, `tflite_flutter` (TensorFlow Lite),
`cupertino_native`, `crypto`, `path_provider`, `timezone`.

## Reference copy

`reference/GardenEar/` is a read-only copy of the owner's earlier Swift app. It
is never built, modified or used as a dependency.
