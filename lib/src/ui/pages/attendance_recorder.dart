import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geo_attendance_system/src/services/attendance_mark.dart';
import 'package:geo_attendance_system/src/services/fetch_offices.dart';
import 'package:geo_attendance_system/src/services/geofence.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';
import 'package:geo_attendance_system/src/ui/widgets/attendance_Marker_buttons.dart';
import 'package:geo_attendance_system/src/ui/widgets/loader_dialog.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

class AttendanceRecorderWidget extends StatefulWidget {
  final User user;

  AttendanceRecorderWidget({this.user});

  @override
  AttendanceRecorderWidgetState createState() =>
      AttendanceRecorderWidgetState();
}

class AttendanceRecorderWidgetState extends State<AttendanceRecorderWidget> {
  Completer<GoogleMapController> _controller = Completer();

  double zoomVal = 5.0;
  OfficeDatabase officeDatabase = new OfficeDatabase();

  // ignore: unused_field
  StreamSubscription<LocationData> _locationSubscription;
  LocationData _currentLocation;
  LocationData _startLocation;
  Set<Marker> _markers = {};
  Set<Circle> _circles = new Set();

  Location _locationService = new Location();
  bool _permission = false;
  String error;
  CameraPosition _currentCameraPosition;
  var rMin;
  var rMax;
  var direction = 1;
  var _radius;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  @override
  void dispose() {
    super.dispose();
    if (_locationSubscription != null) _locationSubscription.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: appbarcolor,
        automaticallyImplyLeading: false,
        leading: new IconButton(
          icon: new Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        //shape: RoundedRectangleBorder(
        // borderRadius: BorderRadius.circular(20.0),
        //  ),
        title: Text(
          "Mark your Attendance",
          style: TextStyle(
              color: Colors.white,
              fontFamily: "Poppins-Medium",
              fontSize: 22,
              letterSpacing: .6,
              fontWeight: FontWeight.bold),
        ),
        elevation: 0.8,
        centerTitle: true,
        bottomOpacity: 0,
      ),
      body: Stack(
        children: <Widget>[
          googleMap(context),
          buildContainer(context),
        ],
      ),
    );
  }

  Widget googleMap(BuildContext context) {
    double _initialLat = 27.2048;
    double _initialLong = 77.4975;
    double _initialZoom = 15;
    return Container(
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: GoogleMap(
        mapType: MapType.normal,
        myLocationEnabled: true,
        circles: _circles,
        initialCameraPosition: CameraPosition(
            target: LatLng(_initialLat, _initialLong), zoom: _initialZoom),
        markers: _markers,
        onMapCreated: (GoogleMapController controller) {
          _controller.complete(controller);
          officeDatabase.getOfficeBasedOnUID(widget.user.uid).then((office) {
            setState(() {
              rMax = office.radius;
              rMin = 3 * office.radius / 5;
              _radius = office.radius;
              Timer.periodic(new Duration(milliseconds: 100), (timer) {
                var radius =
                    _circles.isEmpty ? office.radius : _circles.first.radius;

                if ((radius > rMax) || (radius < rMin)) {
                  direction *= -1;
                }
                var _par = (radius / _radius) - 0.2;
                var radiusFinal = radius + direction * 10;
                if (!mounted) {
                  timer.cancel();
                  return;
                }
                setState(() {
                  _circles.clear();
                  _circles.add(Circle(
                    circleId: CircleId("GeoFenceCircle"),
                    center: LatLng(office.latitude, office.longitude),
                    radius: radiusFinal,
                    strokeColor: Colors.blueGrey,
                    strokeWidth: 5,
                    fillColor: Colors.blueGrey.withOpacity(0.6 * _par),
                  ));
                });
//            circleOption.fillOpacity = 0.6 * _par;

//                circle.setOptions(circleOption);
              });
            });
          });
        },
      ),
    );
  }

  buildContainer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(80.0),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            inOutButton("IN", Colors.green, _callMarkInFunction),
            Spacer(flex: 20),
            inOutButton("OUT", Colors.orangeAccent, _callMarkOutFunction),
          ],
        ),
      ),
    );
  }

  void _callMarkInFunction() {
    if (GeoFenceClass.geofenceState == 'Unknown') {
      showDialog(
          context: context,
          child: Dialog(
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.lightGreen[100],
              ),
              child: Center(
                  child: Text(
                "Attendance recorded successfully",
                style: TextStyle(color: Colors.white, fontSize: 22),
              )),
            ),
          ));
    } else {
      onLoadingDialog(context);
      officeDatabase.getOfficeBasedOnUID(widget.user.uid).then((office) {
        markInAttendance(context, office, _currentLocation, widget.user);
      });
    }
  }

  void _callMarkOutFunction() {
    if (GeoFenceClass.geofenceState == 'Unknown') {
      showDialog(
          context: context,
          child: Dialog(
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.lightGreen[100],
              ),
              child: Center(
                  child: Text(
                "Attendance recorded successfully!",
                style: TextStyle(color: Colors.white, fontSize: 22),
              )),
            ),
          ));
    } else {
      onLoadingDialog(context);
      officeDatabase.getOfficeBasedOnUID(widget.user.uid).then((office) {
        markOutAttendance(context, office, _currentLocation, widget.user);
      });
    }
  }

  Future<void> _gotoLocation(double lat, double long) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: LatLng(lat, long), zoom: 15, tilt: 50.0, bearing: 45.0)));
  }

  initPlatformState() async {
    await _locationService.changeSettings(
        accuracy: LocationAccuracy.BALANCED, interval: 1000);

    LocationData location;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      bool serviceStatus = await _locationService.serviceEnabled();
      print("Service status: $serviceStatus");
      if (serviceStatus) {
        _permission = await _locationService.requestPermission() ==
            PermissionStatus.GRANTED;
        print("Permission: $_permission");
        if (_permission) {
          location = await _locationService.getLocation();

          _locationSubscription = _locationService
              .onLocationChanged()
              .listen((LocationData result) async {
            _currentCameraPosition = CameraPosition(
                target: LatLng(result.latitude, result.longitude),
                zoom: 16,
                tilt: 50.0,
                bearing: 45.0);

            final GoogleMapController controller = await _controller.future;
            controller.animateCamera(
                CameraUpdate.newCameraPosition(_currentCameraPosition));
            if (mounted) {
              setState(() {
                _currentLocation = result;
                _markers.clear();
                _markers.add(Marker(
                    markerId: MarkerId("Current Location"),
                    position: LatLng(result.latitude, result.longitude)));
              });
            }
          });
        }
      } else {
        bool serviceStatusResult = await _locationService.requestService();
        print("Service status activated after request: $serviceStatusResult");
        if (serviceStatusResult) {
          initPlatformState();
        }
      }
    } on PlatformException catch (e) {
      print(e);
      if (e.code == 'PERMISSION_DENIED') {
        error = e.message;
      } else if (e.code == 'SERVICE_STATUS_ERROR') {
        error = e.message;
      }
      location = null;
    }

    setState(() {
      _startLocation = location;
    });
  }
}
