import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gmaps_picker/src/animated_pin.dart';
import 'package:gmaps_picker/src/autocomplete_search.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A function which returns a new marker position.
typedef ChangeMarkerPositionCallback = Future<MarkerPosition> Function();

/// GMapsPicker is used to get the location from google maps. This widget is a
/// full page widget which you can open using a navigator.
///
/// Example:
/// ```
/// final pickedLocation = await Navigator.push<Location>(context, MaterialPageRoute(
///   builder: (context) => GMapsPicker(
///     initialLocation: LatLng(-33.8567844, 151.213108),
///   ),
/// ));
///
/// if (pickedLocation != null) {
///   // A location was picked, do something with.
/// }
/// ```
class GMapsPicker extends StatefulWidget {
  const GMapsPicker({
    Key key,
    @required this.initialLocation,
    this.onMapInitialization,
  }) : super(key: key);

  /// The initial location where the map is first shown. You may use the value
  /// returned by [getCurrentLocation] function here.
  final LatLng initialLocation;

  /// Whatever marker position this callback returns will update the map
  /// position after the map is initialized. It supports zooming of the map
  /// as well.
  final ChangeMarkerPositionCallback onMapInitialization;

  @override
  _GMapsPickerState createState() => _GMapsPickerState();

  /// Get the current location of the user. It throw exceptions if either the
  /// location service is not enabled or the permission to access location has
  /// been denied.
  static Future<LatLng> getCurrentLocation() async {
    final isEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isEnabled) {
      throw LocationServiceNotEnabledException();
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      // We cannot ask for any more permission, it has been permanently denied.
      throw LocationPermissionDeniedForeverException();
    }

    if (permission == LocationPermission.denied) {
      // If it is denied, ask them for permission again.
      final permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw LocationPermissionNotProvidedException();
      }
    }

    final position = await Geolocator.getCurrentPosition();
    return LatLng(position.latitude, position.longitude);
  }
}

class _GMapsPickerState extends State<GMapsPicker> {
  /// The location that is pointed by the marker with additional geocoded
  /// location.
  Location _locationPick;

  /// The current location pointed by the marker shown in the center.
  LatLng _currentMarker;

  /// Whether the map is being moved.
  bool _isMoving = false;

  @override
  void initState() {
    super.initState();

    _currentMarker = LatLng(
      widget.initialLocation.latitude,
      widget.initialLocation.longitude,
    );
    // Reverse geocode the current marker.
    _reverseGeocode();
  }

  /// Reverse geocode from the location pointed by current marker.
  Future<void> _reverseGeocode() async {
    if (_currentMarker == null) {
      return;
    }

    final placemark = await placemarkFromCoordinates(
      _currentMarker.latitude,
      _currentMarker.longitude,
    );
    if (placemark.isNotEmpty) {
      final first = placemark[0];

      setState(() {
        _locationPick = Location(
          placemark: first,
          latlng: _currentMarker,
        );
      });
      return;
    }

    setState(() {
      // There was no address found, no need to retain an older address here.
      _locationPick = null;
    });
  }

  void _onSelectHere() {
    // Return the picked location when popping the nav.
    Navigator.pop(context, _locationPick);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AutoCompleteSearch(),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: <Widget>[
                _buildGoogleMap(context),
                Center(child: AnimatedPin(isAnimating: _isMoving)),
                _buildMyLocationButton(context),
              ],
            ),
          ),
          _buildCurrentLocationBar()
        ],
      ),
      extendBodyBehindAppBar: true,
    );
  }

  Widget _buildCurrentLocationBar() {
    return Material(
      elevation: 4,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _locationPick != null
                    ? [
                        Container(
                          margin: EdgeInsets.only(right: 12),
                          child: Text(
                            _locationPick.formattedAddress,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _locationPick.placemark.country,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ]
                    : [],
              ),
            ),
            ElevatedButton.icon(
              onPressed: _locationPick != null ? _onSelectHere : null,
              icon: Icon(
                Icons.location_pin,
                size: 20,
              ),
              label: Text('Select Here'),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleMap(BuildContext context) {
    return GoogleMap(
      myLocationButtonEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      initialCameraPosition: CameraPosition(target: widget.initialLocation),
      mapType: MapType.normal,
      myLocationEnabled: true,
      zoomControlsEnabled: false,
      onMapCreated: (controller) async {
        // Change the map location once it is initialized.
        if (widget.onMapInitialization != null) {
          final newPos = await widget.onMapInitialization();
          setState(() {
            _currentMarker = newPos.latlng;
          });
          final _ = _reverseGeocode();

          await controller.animateCamera(
            CameraUpdate.newLatLngZoom(newPos.latlng, newPos.zoom),
          );
        }
      },
      onCameraMove: (CameraPosition position) {
        _currentMarker = position.target;
      },
      onCameraMoveStarted: () {
        setState(() {
          _isMoving = true;
        });
      },
      onCameraIdle: () {
        setState(() {
          _isMoving = false;
        });

        // Reverse geocode after the location settles in.
        final _ = _reverseGeocode();
      },
    );
  }

  Widget _buildMyLocationButton(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Positioned(
      top: statusBarHeight + kToolbarHeight + 16,
      right: 12,
      child: ElevatedButton(
        onPressed: () {},
        child: Icon(Icons.my_location),
        style: ButtonStyle(
          minimumSize: MaterialStateProperty.all(Size.zero),
          padding: MaterialStateProperty.all(
            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          shape: MaterialStateProperty.all(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          )),
          backgroundColor: MaterialStateProperty.all(Colors.white),
          foregroundColor: MaterialStateProperty.all(Colors.black),
          overlayColor: MaterialStateProperty.all(Colors.grey.shade200),
        ),
      ),
    );
  }
}

/// A location that was picked from google maps.
class Location {
  Location({
    @required this.placemark,
    @required this.latlng,
  });

  final Placemark placemark;
  final LatLng latlng;

  /// Get the formatted address of this location.
  String get formattedAddress {
    var address = placemark.street ?? '';

    if (placemark.subLocality?.isNotEmpty == true) {
      if (placemark.street?.isNotEmpty == true) {
        address = address + ', ';
      }

      address = address + placemark.subLocality;
    }

    if (placemark.locality?.isNotEmpty == true) {
      if (placemark.street?.isNotEmpty == true ||
          placemark.subLocality?.isNotEmpty == true) {
        address = address + ', ';
      }

      address = address + placemark.locality;
    }

    return address;
  }
}

/// Exception for when location services are not enabled.
class LocationServiceNotEnabledException implements Exception {}

/// Exception for when location permission is not accepted by user.
class LocationPermissionNotProvidedException implements Exception {}

/// Exception for when location permission is denied forever by the user.
class LocationPermissionDeniedForeverException implements Exception {}

/// MarkerPosition defined where the marker is located at on the map.
class MarkerPosition {
  MarkerPosition({
    @required this.latlng,
    @required this.zoom,
  });

  /// Latitude of the location.
  final LatLng latlng;

  /// Zoom factor on google maps.
  final double zoom;
}
