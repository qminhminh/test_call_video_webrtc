// ignore_for_file: prefer_const_constructors, avoid_print, deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signalling.service.dart';

class CallScreen extends StatefulWidget {
  final String callerId, calleeId;
  final dynamic offer;
  const CallScreen({
    super.key,
    this.offer,
    required this.callerId,
    required this.calleeId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  // socket instance
  final socket = SignallingService.instance.socket;

  // videoRenderer for localPeer
  final _localRTCVideoRenderer = RTCVideoRenderer();

  // videoRenderer for remotePeer
  final _remoteRTCVideoRenderer = RTCVideoRenderer();

  // mediaStream for localPeer
  MediaStream? _localStream;

  // RTC peer connection
  RTCPeerConnection? _rtcPeerConnection;

  // list of rtcCandidates to be sent over signalling
  List<RTCIceCandidate> rtcIceCadidates = [];

  // media status
  bool isAudioOn = true, isVideoOn = true, isFrontCameraSelected = true;

  @override
  void initState() {
    // initializing renderers
    _localRTCVideoRenderer.initialize();
    _remoteRTCVideoRenderer.initialize();

    // setup Peer Connection
    _setupPeerConnection();
    super.initState();
  }

  @override
  void setState(fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  // Hàm trợ giúp: Kiểm tra candidate có phải IPv4 hay không
  bool _isIPv4(String candidate) {
    RegExp ipv4Regex = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
    return ipv4Regex.hasMatch(candidate);
  }

  // Hàm lọc SDP: chỉ giữ lại những dòng chứa candidate có địa chỉ IPv4
  Future<RTCSessionDescription> _filterSDPForIPv4(
      RTCSessionDescription sdpDescription) async {
    String sdp = sdpDescription.sdp!;
    List<String> lines = sdp.split('\n');
    List<String> filteredLines = [];
    for (String line in lines) {
      if (line.startsWith('a=candidate:')) {
        // Giữ lại dòng candidate nếu chứa địa chỉ IPv4
        if (_isIPv4(line)) {
          filteredLines.add(line);
        }
      } else {
        filteredLines.add(line);
      }
    }
    String filteredSdp = filteredLines.join('\n');
    return RTCSessionDescription(filteredSdp, sdpDescription.type);
  }

  _setupPeerConnection() async {
    // create peer connection
    _rtcPeerConnection = await createPeerConnection({
      'iceServers': [
        {
          'urls': "",
        },
        {
          'urls': '',
          'username': '',
          'credential': "",
        },
      ],
    });

    // listen for remotePeer mediaTrack event
    _rtcPeerConnection!.onTrack = (event) {
      _remoteRTCVideoRenderer.srcObject = event.streams.first;
      setState(() {});
    };

    // get localStream
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': isAudioOn,
      'video': isVideoOn
          ? {'facingMode': isFrontCameraSelected ? 'user' : 'environment'}
          : false,
    });

    // add mediaTrack to peerConnection
    _localStream!.getTracks().forEach((track) {
      _rtcPeerConnection!.addTrack(track, _localStream!);
    });

    // set source for local video renderer
    _localRTCVideoRenderer.srcObject = _localStream;
    setState(() {});

    // For incoming call
    if (widget.offer != null) {
      // Lắng nghe ICE candidate từ remote (với filter)
      socket!.on("IceCandidate", (data) {
        String candidate = data["iceCandidate"]["candidate"];
        // Lọc candidate: chỉ xử lý nếu candidate chứa địa chỉ IPv4
        if (!_isIPv4(candidate)) {
          print("Bỏ candidate IPv6: $candidate");
          return;
        }
        String sdpMid = data["iceCandidate"]["id"];
        int sdpMLineIndex = data["iceCandidate"]["label"];

        _rtcPeerConnection!.addCandidate(RTCIceCandidate(
          candidate,
          sdpMid,
          sdpMLineIndex,
        ));
        print("IceCandidate nhận: $candidate");
        setState(() {});
      });

      print("Offer: ${widget.offer}");

      // Tạo một đối tượng RTCSessionDescription từ offer nhận được
      RTCSessionDescription remoteOffer =
          RTCSessionDescription(widget.offer["sdp"], widget.offer["type"]);

      // Lọc SDP của offer, chỉ giữ lại các candidate IPv4
      RTCSessionDescription filteredRemoteOffer =
          await _filterSDPForIPv4(remoteOffer);

      // Set remote description với SDP đã được lọc
      await _rtcPeerConnection!.setRemoteDescription(filteredRemoteOffer);

      // Tạo SDP answer
      RTCSessionDescription answer = await _rtcPeerConnection!.createAnswer();

      // Lọc SDP answer: chỉ giữ lại các candidate IPv4
      RTCSessionDescription filteredAnswer = await _filterSDPForIPv4(answer);

      // Set local description với SDP answer đã được lọc
      await _rtcPeerConnection!.setLocalDescription(filteredAnswer);

      // Gửi SDP answer về remote qua signalling
      socket!.emit("answerCall", {
        "callerId": widget.callerId,
        "sdpAnswer": filteredAnswer.toMap(),
      });
    }
    // For Outgoing Call
    else {
      // Lắng nghe ICE candidate local: chỉ thêm candidate nếu candidate là IPv4
      _rtcPeerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (!_isIPv4(candidate.candidate ?? "")) {
          print("Bỏ candidate IPv6 local: ${candidate.candidate}");
          return;
        }
        rtcIceCadidates.add(candidate);
      };

      // Khi call được remote chấp nhận
      socket!.on("callAnswered", (data) async {
        RTCSessionDescription remoteSdp = RTCSessionDescription(
            data["sdpAnswer"]["sdp"], data["sdpAnswer"]["type"]);

        RTCSessionDescription filteredSdp = await _filterSDPForIPv4(remoteSdp);

        await _rtcPeerConnection!.setRemoteDescription(filteredSdp);
        // Gửi các ICE candidate đã thu thập (chỉ candidate IPv4)
        for (RTCIceCandidate candidate in rtcIceCadidates) {
          socket!.emit("IceCandidate", {
            "calleeId": widget.calleeId,
            "iceCandidate": {
              "id": candidate.sdpMid,
              "label": candidate.sdpMLineIndex,
              "candidate": candidate.candidate,
            }
          });
          print("Gửi ICE Candidate: ${candidate.candidate}");
          print("sdpMid: ${candidate.sdpMid}");
          print("sdpMLineIndex: ${candidate.sdpMLineIndex}");
        }
      });

      // Tạo SDP Offer
      RTCSessionDescription offer = await _rtcPeerConnection!.createOffer();

      // Lọc SDP offer: chỉ giữ candidate IPv4
      RTCSessionDescription filteredOffer = await _filterSDPForIPv4(offer);

      // Set SDP offer local
      await _rtcPeerConnection!.setLocalDescription(filteredOffer);

      // Gửi offer đến remote qua signalling
      socket!.emit('makeCall', {
        "calleeId": widget.calleeId,
        "sdpOffer": filteredOffer.toMap(),
      });
    }
  }

  _leaveCall() {
    Navigator.pop(context);
  }

  _toggleMic() {
    isAudioOn = !isAudioOn;
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = isAudioOn;
    });
    setState(() {});
  }

  _toggleCamera() {
    isVideoOn = !isVideoOn;
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = isVideoOn;
    });
    setState(() {});
  }

  _switchCamera() {
    isFrontCameraSelected = !isFrontCameraSelected;
    _localStream?.getVideoTracks().forEach((track) {
      track.switchCamera();
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text("P2P Call App"),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(children: [
                RTCVideoView(
                  _remoteRTCVideoRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: SizedBox(
                    height: 150,
                    width: 120,
                    child: RTCVideoView(
                      _localRTCVideoRenderer,
                      mirror: isFrontCameraSelected,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                )
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: Icon(isAudioOn ? Icons.mic : Icons.mic_off),
                    onPressed: _toggleMic,
                  ),
                  IconButton(
                    icon: const Icon(Icons.call_end),
                    iconSize: 30,
                    onPressed: _leaveCall,
                  ),
                  IconButton(
                    icon: const Icon(Icons.cameraswitch),
                    onPressed: _switchCamera,
                  ),
                  IconButton(
                    icon: Icon(isVideoOn ? Icons.videocam : Icons.videocam_off),
                    onPressed: _toggleCamera,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _localRTCVideoRenderer.dispose();
    _remoteRTCVideoRenderer.dispose();
    _localStream?.dispose();
    _rtcPeerConnection?.dispose();
    super.dispose();
  }
}
      
