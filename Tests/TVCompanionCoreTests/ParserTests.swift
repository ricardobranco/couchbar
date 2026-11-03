import Testing
@testable import TVCompanionCore

struct ParserTests {
    @Test func devicesListKeepsSerialStateAndModel() {
        let output = """
        List of devices attached
        ABC123XYZ45678         device usb:12345678X product:lynx model:Pixel_7a device:lynx transport_id:39
        adb-1A2B3C4D5E6F7A8B9-a1B2c3._adb-tls-connect._tcp device product:G08_4K_GB model:Smart_TV_Pro device:G08 transport_id:87
        192.168.0.50:5555      offline

        """
        let devices = ADBDevice.parse(output)
        #expect(devices.count == 3)
        #expect(devices[1].serial == "adb-1A2B3C4D5E6F7A8B9-a1B2c3._adb-tls-connect._tcp")
        #expect(devices[1].model == "Smart_TV_Pro")
        #expect(devices[1].isOnline)
        #expect(!devices[2].isOnline)
    }

    @Test func mdnsServicesSkipHeader() {
        let output = """
        List of discovered mdns services
        adb-1A2B3C4D5E6F7A8B9-a1B2c3\t_adb-tls-connect._tcp\t192.168.0.42:37887
        adb-1A2B3C4D5E6F7A8B9\t_adb._tcp\t192.168.0.42:5555
        """
        let services = MDNSService.parse(output)
        #expect(services.count == 2)
        #expect(services[0].isTLS)
        #expect(services[0].address == "192.168.0.42:37887")
        #expect(!services[1].isTLS)
    }

    @Test func volumeLevel() {
        let level = VolumeLevel.parse("[V] Connecting to AudioService\n[V] volume is 15 in range [0..100]\n")
        #expect(level == VolumeLevel(current: 15, range: 0...100))
        #expect(VolumeLevel.parse("Error: no service") == nil)
    }

    @Test func volumeControl() {
        #expect(VolumeControl.parse("mIsAbsoluteVolumeBehaviorEnabled: false\n  mSystemAudioActivated: true\n") == .stepped)
        #expect(VolumeControl.parse("mIsAbsoluteVolumeBehaviorEnabled: true\n  mSystemAudioActivated: true\n") == .absolute)
        #expect(VolumeControl.parse("mIsAbsoluteVolumeBehaviorEnabled: false\n  mSystemAudioActivated: false\n") == .absolute)
        #expect(VolumeControl.parse("Can't find service: hdmi_control") == .absolute)
    }

    @Test func ipAddress() {
        let output = """
        1: lo    inet 127.0.0.1/8 scope host lo\\       valid_lft forever preferred_lft forever
        16: wlan0    inet 192.168.0.42/24 brd 192.168.0.255 scope global wlan0\\       valid_lft forever preferred_lft forever
        """
        #expect(IPAddress.parse(output) == "192.168.0.42")
        #expect(IPAddress.parse("1: lo    inet 127.0.0.1/8 scope host lo") == nil)
    }

    @Test func powerAndForegroundApp() {
        #expect(PowerState.parse("  mWakefulness=Awake\n") == .awake)
        #expect(PowerState.parse("  mWakefulness=Asleep\n")?.isOn == false)
        #expect(ForegroundApp.parse("  mCurrentFocus=Window{9094d63 u0 com.tcl.tv/com.tcl.tv.TVActivity}") == "com.tcl.tv")
    }

    @Test func tvInputsMapHardwareIDsToHDMIPorts() {
        let dump = """
          inputMap: inputId -> TvInputState
            com.tcl.tvinput/.TvPassThroughService/HW3: info: TvInputInfo{id=com.tcl.tvinput/.TvPassThroughService/HW3, pkg=com.tcl.tvinput, service=com.tcl.tvinput.TvPassThroughService}; state: 2
            com.tcl.tvinput/.TvPassThroughService/HW17: info: TvInputInfo{id=com.tcl.tvinput/.TvPassThroughService/HW17, pkg=com.tcl.tvinput, service=com.tcl.tvinput.TvPassThroughService}; state: 1
            com.tcl.tvinput/.TvPassThroughService/HW18: info: TvInputInfo{id=com.tcl.tvinput/.TvPassThroughService/HW18, pkg=com.tcl.tvinput, service=com.tcl.tvinput.TvPassThroughService}; state: 0
            com.tcl.tvinput/.TunerInputService/HW2: info: TvInputInfo{id=com.tcl.tvinput/.TunerInputService/HW2, pkg=com.tcl.tvinput, service=com.tcl.tvinput.TunerInputService}; state: 0
            com.tcl.tvinput/.TvPassThroughService/HW15: info: TvInputInfo{id=com.tcl.tvinput/.TvPassThroughService/HW15, pkg=com.tcl.tvinput, service=com.tcl.tvinput.TvPassThroughService}; state: 1
            com.tcl.tvinput/.TvPassThroughService/HDMI100004: info: TvInputInfo{id=com.tcl.tvinput/.TvPassThroughService/HDMI100004, pkg=com.tcl.tvinput, service=com.tcl.tvinput.TvPassThroughService}; state: 1
          mHardwareList:
            TvInputHardwareInfo {id=15, type=9, audio_type=0, audio_addr=null, hdmi_port=1, cable_connection_status=2}
            TvInputHardwareInfo {id=17, type=9, audio_type=0, audio_addr=null, hdmi_port=3, cable_connection_status=2}
            TvInputHardwareInfo {id=18, type=9, audio_type=0, audio_addr=null, hdmi_port=4, cable_connection_status=2}
        """
        let inputs = TVInput.parse(dump)
        #expect(inputs.map(\.defaultName) == ["Live TV", "HDMI 1", "HDMI 3", "HDMI 4"])
        #expect(inputs[1].id == "com.tcl.tvinput/.TvPassThroughService/HW15")
        #expect(inputs[1].state == .standby)
        #expect(inputs[3].state == .connected)
    }

    @Test func nowPlayingPrefersPlayingSession() {
        let dump = """
          Media button session is null
          Sessions Stack - have 3 sessions:
            androidx.media3.session.id. com.spotify.tv.android/androidx.media3.session.id. (userId=0)
              ownerPid=4613, ownerUid=10109, userId=0
              package=com.spotify.tv.android
              active=true
              state=PlaybackState {state=PAUSED(2), position=193807, buffered position=0, speed=0.0}
              metadata: size=22, description=Take It Or Leave It, The Strokes, null
            YouTube com.google.android.youtube.tv/YouTube (userId=0)
              package=com.google.android.youtube.tv
              state=PlaybackState {state=PLAYING(3), position=1000, buffered position=0, speed=1.0}
              metadata: size=10, description=Live at Glastonbury, Arctic Monkeys, Topic, null
            BluetoothMediaBrowserService com.android.bluetooth/BluetoothMediaBrowserService (userId=0)
              package=com.android.bluetooth
              state=PlaybackState {state=ERROR(7), position=0}
              metadata: null
        Audio playback (lastly played comes first)
        """
        let nowPlaying = NowPlaying.parse(dump)
        #expect(nowPlaying?.package == "com.google.android.youtube.tv")
        #expect(nowPlaying?.title == "Live at Glastonbury")
        #expect(nowPlaying?.artist == "Arctic Monkeys, Topic")
        #expect(nowPlaying?.isPlaying == true)
    }

    @Test func nowPlayingFallsBackToPausedSession() {
        let dump = """
          Sessions Stack - have 1 sessions:
            x com.spotify.tv.android/x (userId=0)
              package=com.spotify.tv.android
              state=PlaybackState {state=PAUSED(2), position=193807}
              metadata: size=22, description=Take It Or Leave It, The Strokes, null
        """
        let nowPlaying = NowPlaying.parse(dump)
        #expect(nowPlaying == NowPlaying(package: "com.spotify.tv.android", title: "Take It Or Leave It", artist: "The Strokes", isPlaying: false))
        #expect(NowPlaying.parse("Sessions Stack - have 0 sessions:\n") == nil)
    }

    @Test func macAddressPrefersInterfaceThatIsUp() {
        let output = """
        14: eth0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc pfifo_fast state DOWN mode DEFAULT group default qlen 1000\\    link/ether 2c:e0:32:7e:23:de brd ff:ff:ff:ff:ff:ff
        16: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DORMANT group default qlen 3000\\    link/ether 02:11:22:33:44:55 brd ff:ff:ff:ff:ff:ff
        """
        #expect(MACAddress.parse(output) == "02:11:22:33:44:55")
    }

    @Test func scrcpyArgumentsFollowOptions() {
        var options = MirrorOptions()
        options.forwardAudio = true
        options.allowControl = false
        let arguments = Scrcpy.arguments(serial: "tv", title: "Living room TV", options: options)
        #expect(arguments.contains("--serial=tv"))
        #expect(arguments.contains("--audio-dup"))
        #expect(arguments.contains("--no-control"))
        #expect(!arguments.contains("--no-audio"))
    }

    @Test func unknownAppsGetReadableNames() {
        #expect(TVApp(package: "com.netflix.ninja").name == "Netflix")
        #expect(TVApp(package: "com.example.coolplayer.tv").name == "Coolplayer")
    }
}

struct BadgingTests {
    @Test func bannerAndLargestIcon() {
        let output = """
        package: name='com.netflix.ninja' versionCode='27249'
        application-label:'Netflix'
        application-icon-160:'res/mipmap-mdpi-v4/ic_launcher.png'
        application-icon-480:'res/mipmap-xxhdpi-v4/ic_launcher.png'
        application-icon-65534:'res/mipmap-mdpi-v4/ic_launcher.png'
        application: label='Netflix' icon='res/mipmap-mdpi-v4/ic_launcher.png' banner='res/mipmap-mdpi-v4/ic_banner.png'
        """
        #expect(Badging.parse(output) == Badging(label: "Netflix", banner: "res/mipmap-mdpi-v4/ic_banner.png", largestIcon: "res/mipmap-xxhdpi-v4/ic_launcher.png"))
    }

    @Test func noBannerNoIcon() {
        #expect(Badging.parse("application: label='HBO Max' icon=''") == Badging(label: "HBO Max", banner: nil, largestIcon: nil))
        #expect(Badging.parse("package: name='x'") == nil)
    }
}
